import AppCore
@preconcurrency import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation

enum SystemAudioTapError: LocalizedError {
    case osStatus(OSStatus, context: String)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status, let context):
            return "\(context) (OSStatus \(status))"
        }
    }
}

/// One replaceable Core Audio graph. It owns no file writer; PCM is synchronously handed to
/// RecorderPCMWriterPipeline through RecorderBackendCallbacks.
final class SystemAudioProcessTapSession: @unchecked Sendable, RecorderCaptureBackend {
    let identity = RecorderCaptureBackendIdentity.coreAudio

    private struct PropertyRegistration {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let stateLock = NSLock()
    private let lifecycleLock = NSRecursiveLock()
    private let ioQueue = DispatchQueue(label: "NikoMusicHub.SystemAudioProcessTapSession.io", qos: .userInitiated)
    private let listenerQueue = DispatchQueue(label: "NikoMusicHub.SystemAudioProcessTapSession.listeners")
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var anchorDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var sourceFormat: AVAudioFormat?
    private var callbacks: RecorderBackendCallbacks?
    private var generation = 0
    private var running = false
    private var propertyRegistrations: [PropertyRegistration] = []
    private let makeTapDescription: @Sendable () -> CATapDescription

    /// The recorder taps every process; the permission probe taps only this process.
    init(makeTapDescription: @escaping @Sendable () -> CATapDescription = {
        SystemAudioTapConfiguration.makeGlobalTapDescription()
    }) {
        self.makeTapDescription = makeTapDescription
    }

    deinit { tearDown() }

    func start(generation: Int, callbacks: RecorderBackendCallbacks) async throws {
        try startSynchronously(generation: generation, callbacks: callbacks)
    }

    private func startSynchronously(generation: Int, callbacks: RecorderBackendCallbacks) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !stateLock.withLock({ running }) else {
            throw RecorderError.apiError("Core Audio backend already active")
        }

        do {
            let processTap = try createProcessTap()
            tapID = processTap.id
            let outputDevice = try readDefaultSystemOutputDevice()
            anchorDeviceID = outputDevice.id
            aggregateDeviceID = try createAggregateDevice(
                tapUID: processTap.uid,
                outputDeviceUID: outputDevice.uid
            )
            // kAudioTapPropertyFormat describes the mixer's format (48 kHz here even
            // when the speakers run at 44.1 kHz), but the IO proc runs on the
            // aggregate's clock, i.e. its main sub-device, and drift compensation
            // resamples the tap into that clock. Labeling the frames with the tap's
            // rate made every recording on a 44.1 kHz device play 8.8 % fast and sharp
            // (a 440 Hz tone came back at 479 Hz), so take the rate from the aggregate.
            let streamDescription = SystemAudioTapConfiguration.deliveredStreamDescription(
                tapFormat: try readTapStreamDescription(tapID: tapID),
                aggregateSampleRate: try readNominalSampleRate(deviceID: aggregateDeviceID)
            )
            guard let deliveredFormat = AVAudioFormat(streamDescription: streamDescription) else {
                throw RecorderError.apiError("Unsupported tap audio format")
            }

            stateLock.withLock {
                self.generation = generation
                self.callbacks = callbacks
                sourceFormat = deliveredFormat
                running = true
            }
            callbacks.onMetadata(RecorderBackendMetadata(
                outputDeviceUID: outputDevice.uid,
                sourceSampleRate: deliveredFormat.sampleRate,
                sourceChannelCount: Int(deliveredFormat.channelCount)
            ))
            try installIOProc(deviceID: aggregateDeviceID)
            try installPropertyListeners(anchorDeviceID: outputDevice.id)
            try startDevice(deviceID: aggregateDeviceID)
        } catch {
            tearDown()
            throw error
        }
    }

    func stop() async { tearDown() }

    private func tearDown() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        stateLock.withLock { running = false }
        removePropertyListeners()

        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        // The aggregate references the tap, so destroy it before the tap itself.
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        anchorDeviceID = kAudioObjectUnknown
        stateLock.withLock {
            sourceFormat = nil
            callbacks = nil
        }
    }

    private func createProcessTap() throws -> (id: AudioObjectID, uid: String) {
        let description = makeTapDescription()
        description.uuid = UUID()
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &id)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create system audio tap")
        }
        return (id, description.uuid.uuidString)
    }

    private func createAggregateDevice(tapUID: String, outputDeviceUID: String) throws -> AudioObjectID {
        let description = SystemAudioTapConfiguration.makeAggregateDeviceDescription(
            tapUID: tapUID,
            outputDeviceUID: outputDeviceUID
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create aggregate device")
        }
        return id
    }

    private func readTapStreamDescription(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var description = AudioStreamBasicDescription()
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &description)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read tap format")
        }
        return description
    }

    /// The clock rate the aggregate's IO proc actually runs at.
    private func readNominalSampleRate(deviceID: AudioObjectID) throws -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Double>.size)
        var sampleRate: Double = 0
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read aggregate device sample rate")
        }
        return sampleRate
    }

    private func readDefaultSystemOutputDevice() throws -> (id: AudioObjectID, uid: String) {
        do {
            return try readOutputDevice(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        } catch {
            return try readOutputDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        }
    }

    private func readOutputDevice(selector: AudioObjectPropertySelector) throws -> (id: AudioObjectID, uid: String) {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read output device")
        }

        var uid = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read output device UID")
        }
        return (deviceID, uid as String)
    }

    private func installIOProc(deviceID: AudioObjectID) throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, ioQueue) { [weak self] _, inputData, _, _, _ in
            self?.handleAudio(inputData)
        }
        guard status == noErr, let procID else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create IO proc")
        }
        ioProcID = procID
    }

    private func startDevice(deviceID: AudioObjectID) throws {
        guard let ioProcID else { throw RecorderError.apiError("IO proc not installed") }
        let status = AudioDeviceStart(deviceID, ioProcID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not start aggregate device")
        }
    }

    private func handleAudio(_ inputData: UnsafePointer<AudioBufferList>) {
        let snapshot = stateLock.withLock { () -> (Bool, Int, AVAudioFormat?, RecorderBackendCallbacks?) in
            (running, generation, sourceFormat, callbacks)
        }
        guard snapshot.0, let format = snapshot.2, let callbacks = snapshot.3 else { return }
        guard inputData.pointee.mNumberBuffers > 0,
              let frames = RecorderPCMBufferLayout.frameCount(
                  bufferList: inputData,
                  streamDescription: format.streamDescription.pointee
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil)
        else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        buffer.frameLength = min(frames, buffer.frameCapacity)
        guard buffer.frameLength > 0 else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        let bytes = RecorderPCMBufferLayout.usableByteCount(bufferList: inputData)
        guard bytes > 0 else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        _ = callbacks.onPCM(snapshot.1, format, buffer, bytes)
    }

    private func installPropertyListeners(anchorDeviceID: AudioObjectID) throws {
        let system = AudioObjectID(kAudioObjectSystemObject)
        try addPropertyListener(
            objectID: system,
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try addPropertyListener(
            objectID: system,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try addPropertyListener(
            objectID: anchorDeviceID,
            selector: kAudioDevicePropertyNominalSampleRate,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try addPropertyListener(
            objectID: anchorDeviceID,
            selector: kAudioDevicePropertyDeviceIsAlive,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try addPropertyListener(
            objectID: anchorDeviceID,
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput
        )
    }

    private func addPropertyListener(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            listenerQueue.async { [weak self] in
                guard let self else { return }
                let callback: RecorderBackendCallbacks? = stateLock.withLock {
                    running ? callbacks : nil
                }
                callback?.onRouteChange()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, listenerQueue, block)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not observe audio route property \(selector)")
        }
        propertyRegistrations.append(PropertyRegistration(objectID: objectID, address: address, block: block))
    }

    private func removePropertyListeners() {
        for var registration in propertyRegistrations {
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &registration.address,
                listenerQueue,
                registration.block
            )
        }
        propertyRegistrations.removeAll()
    }
}

enum RecorderPCMBufferLayout {
    static func frameCount(
        bufferList: UnsafePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> AVAudioFrameCount? {
        let bytesPerFrame = streamDescription.mBytesPerFrame
        guard bytesPerFrame > 0 else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        var minimum: UInt32?
        for buffer in buffers {
            guard buffer.mData != nil, buffer.mDataByteSize > 0 else { continue }
            let frames = buffer.mDataByteSize / bytesPerFrame
            guard frames > 0 else { continue }
            minimum = min(minimum ?? frames, frames)
        }
        guard let minimum, minimum > 0 else { return nil }
        return AVAudioFrameCount(minimum)
    }

    static func usableByteCount(bufferList: UnsafePointer<AudioBufferList>) -> Int64 {
        UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            .reduce(into: Int64(0)) { total, buffer in
                if buffer.mData != nil { total += Int64(buffer.mDataByteSize) }
            }
    }
}

enum SystemAudioTapConfiguration {
    static let tapName = "NikoMusicHub-SystemTap"
    static let aggregateDeviceName = "NikoMusicHub-Aggregate"

    static func makeGlobalTapDescription() -> CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = tapName
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted
        return description
    }

    static func makeAggregateDeviceDescription(tapUID: String, outputDeviceUID: String) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]] as CFArray,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true
            ]] as CFArray,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false
        ]
    }

    /// The format the aggregate's IO proc really delivers: the tap's sample
    /// layout at the aggregate's clock rate. `kAudioTapPropertyFormat` reports
    /// the mixer's rate, which differs from the aggregate's main sub-device
    /// whenever the output device is not running at that rate; drift
    /// compensation resamples the tap into the aggregate's clock, so frames must
    /// be labeled with the aggregate rate or the file plays at the wrong speed.
    static func deliveredStreamDescription(
        tapFormat: AudioStreamBasicDescription,
        aggregateSampleRate: Double
    ) -> AudioStreamBasicDescription {
        var description = tapFormat
        if aggregateSampleRate > 0 {
            description.mSampleRate = aggregateSampleRate
        }
        return description
    }
}

private extension AVAudioFormat {
    convenience init?(streamDescription: AudioStreamBasicDescription) {
        var description = streamDescription
        self.init(streamDescription: &description)
    }
}
