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
    /// Published the moment the tap exists (it mutes from creation), outside
    /// `lifecycleLock`, so `releaseMute` never waits for a stuck HAL call.
    private let tapObject = ProcessTapObjectCell()
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var anchorDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var sourceFormat: AVAudioFormat?
    /// Picks the tap's buffers out of the aggregate's input list (which also carries the
    /// output device's own inputs). Resolved once per start.
    private var tapInput: SystemAudioTapInputSelector?
    private var callbacks: RecorderBackendCallbacks?
    private var generation = 0
    private var running = false
    private var propertyRegistrations: [PropertyRegistration] = []
    private let makeTapDescription: @Sendable () -> CATapDescription
    private let hal: SystemAudioTapHAL

    /// The recorder taps every process; the permission probe taps only this process.
    init(
        makeTapDescription: @escaping @Sendable () -> CATapDescription = {
            SystemAudioTapConfiguration.makeGlobalTapDescription()
        },
        hal: SystemAudioTapHAL = .live
    ) {
        self.makeTapDescription = makeTapDescription
        self.hal = hal
    }

    deinit { tearDown() }

    func start(generation: Int, callbacks: RecorderBackendCallbacks) async throws {
        try startSynchronously(generation: generation, callbacks: callbacks)
    }

    /// Blocking form for callers that run HAL work on their own queue (the permission probe).
    func startSynchronously(generation: Int, callbacks: RecorderBackendCallbacks) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !stateLock.withLock({ running }) else {
            throw RecorderError.apiError("Core Audio backend already active")
        }

        do {
            let processTap = try createProcessTap()
            guard tapObject.publish(processTap.id) else {
                hal.destroyProcessTap(processTap.id)
                throw Self.muteReleasedError
            }
            try throwIfMuteReleased()
            let outputDevice = try readDefaultSystemOutputDevice()
            try throwIfMuteReleased()
            anchorDeviceID = outputDevice.id
            try throwIfMuteReleased()
            aggregateDeviceID = try createAggregateDevice(
                tapUID: processTap.uid,
                outputDeviceUID: outputDevice.uid
            )
            try throwIfMuteReleased()
            // kAudioTapPropertyFormat describes the mixer's format (48 kHz here even
            // when the speakers run at 44.1 kHz), but the IO proc runs on the
            // aggregate's clock, i.e. its main sub-device, and drift compensation
            // resamples the tap into that clock. Labeling the frames with the tap's
            // rate made every recording on a 44.1 kHz device play 8.8 % fast and sharp
            // (a 440 Hz tone came back at 479 Hz), so take the rate from the aggregate.
            // Every HAL use below is bracketed by a mute check: a check before the
            // call skips a tap/aggregate that releaseMute already destroyed, and a
            // check after observes a release that landed during the call so the late
            // return tears down instead of starting a device on a destroyed tap.
            // releaseMute never waits on lifecycleLock, preserving the deadline.
            let tapFormat = try readTapStreamDescription(tapID: processTap.id)
            try throwIfMuteReleased()
            let aggregateSampleRate = try readNominalSampleRate(deviceID: aggregateDeviceID)
            try throwIfMuteReleased()
            let streamDescription = SystemAudioTapConfiguration.deliveredStreamDescription(
                tapFormat: tapFormat,
                aggregateSampleRate: aggregateSampleRate
            )
            guard let deliveredFormat = AVAudioFormat(streamDescription: streamDescription) else {
                throw RecorderError.apiError("Unsupported tap audio format")
            }
            // The aggregate's input list also carries the output device's own input
            // streams (an audio interface's mics), ahead of the tap's. Only the tap's
            // buffers may reach the pipeline; an unrecognized layout fails this attempt.
            let aggregateInputs = try readInputStreamChannels(deviceID: aggregateDeviceID, of: "aggregate device")
            try throwIfMuteReleased()
            let outputDeviceInputs = try readInputStreamChannels(deviceID: outputDevice.id, of: "output device")
            try throwIfMuteReleased()
            let inputLayout = try SystemAudioTapInputLayout.resolve(
                aggregateInputChannels: aggregateInputs,
                outputDeviceInputChannels: outputDeviceInputs,
                tapFormat: tapFormat
            )

            try establishRunning(
                generation: generation,
                callbacks: callbacks,
                format: deliveredFormat,
                tapInput: SystemAudioTapInputSelector(layout: inputLayout)
            )
            try throwIfMuteReleased()
            callbacks.onMetadata(RecorderBackendMetadata(
                outputDeviceUID: outputDevice.uid,
                sourceSampleRate: deliveredFormat.sampleRate,
                sourceChannelCount: Int(deliveredFormat.channelCount)
            ))
            try throwIfMuteReleased()
            try installIOProc(deviceID: aggregateDeviceID)
            try throwIfMuteReleased()
            try installPropertyListeners(anchorDeviceID: outputDevice.id)
            try throwIfMuteReleased()
            try startDevice(deviceID: aggregateDeviceID)
            try throwIfMuteReleased()
        } catch {
            tearDown()
            throw error
        }
    }

    func stop() async { tearDown() }

    func stopSynchronously() { tearDown() }

    /// Destroys the process tap right away, from any thread, without `lifecycleLock`: a
    /// start stuck in a later HAL call must not keep the app muted. The stuck start
    /// notices when it returns, tears down the rest, and can never publish a tap again.
    func releaseMute() {
        // Hold stateLock across running + take so establishRunning (check + set
        // under the same lock) is atomic against this: either the start sets
        // running before the release destroys the tap (and its next guard aborts),
        // or the release wins and the start never sets running.
        let id: AudioObjectID?
        stateLock.lock()
        running = false
        id = tapObject.take(permanently: true)
        stateLock.unlock()
        if let id {
            hal.destroyProcessTap(id)
        }
    }

    private static let muteReleasedError = RecorderError.apiError("Tap released while starting")

    private func throwIfMuteReleased() throws {
        if tapObject.isReleased { throw Self.muteReleasedError }
    }

    /// Sets running only while the mute is still held, atomically against releaseMute.
    private func establishRunning(
        generation: Int,
        callbacks: RecorderBackendCallbacks,
        format: AVAudioFormat,
        tapInput: SystemAudioTapInputSelector
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        if tapObject.isReleased { throw Self.muteReleasedError }
        self.generation = generation
        self.callbacks = callbacks
        sourceFormat = format
        self.tapInput = tapInput
        running = true
    }

    private func tearDown() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        stateLock.withLock { running = false }
        removePropertyListeners()

        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            hal.stopDevice(aggregateDeviceID, ioProcID)
            hal.destroyIOProc(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        // The aggregate references the tap, so destroy it before the tap itself.
        if aggregateDeviceID != kAudioObjectUnknown {
            hal.destroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if let id = tapObject.take(permanently: false) {
            hal.destroyProcessTap(id)
        }
        anchorDeviceID = kAudioObjectUnknown
        stateLock.withLock {
            sourceFormat = nil
            tapInput = nil
            callbacks = nil
        }
    }

    private func createProcessTap() throws -> (id: AudioObjectID, uid: String) {
        let description = makeTapDescription()
        description.uuid = UUID()
        let (status, id) = hal.createProcessTap(description)
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
        let (status, id) = hal.createAggregateDevice(description)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create aggregate device")
        }
        return id
    }

    private func readTapStreamDescription(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        let (status, description) = hal.readTapFormat(tapID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read tap format")
        }
        return description
    }

    /// The clock rate the aggregate's IO proc actually runs at.
    private func readNominalSampleRate(deviceID: AudioObjectID) throws -> Double {
        let (status, sampleRate) = hal.readNominalSampleRate(deviceID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read aggregate device sample rate")
        }
        return sampleRate
    }

    private func readInputStreamChannels(deviceID: AudioObjectID, of device: String) throws -> [UInt32] {
        let (status, channels) = hal.readInputStreamChannels(deviceID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read \(device) input streams")
        }
        return channels
    }

    private func readDefaultSystemOutputDevice() throws -> (id: AudioObjectID, uid: String) {
        try hal.readDefaultSystemOutputDevice()
    }

    private func installIOProc(deviceID: AudioObjectID) throws {
        try throwIfMuteReleased()
        let (status, procID) = hal.createIOProc(deviceID, ioQueue) { [weak self] _, inputData, _, _, _ in
            self?.handleAudio(inputData)
        }
        guard status == noErr, let procID else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create IO proc")
        }
        ioProcID = procID
    }

    private func startDevice(deviceID: AudioObjectID) throws {
        try throwIfMuteReleased()
        guard let ioProcID else { throw RecorderError.apiError("IO proc not installed") }
        let status = hal.startDevice(deviceID, ioProcID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not start aggregate device")
        }
    }

    private func handleAudio(_ inputData: UnsafePointer<AudioBufferList>) {
        let snapshot = stateLock.withLock {
            () -> (Bool, Int, AVAudioFormat?, SystemAudioTapInputSelector?, RecorderBackendCallbacks?) in
            (running, generation, sourceFormat, tapInput, callbacks)
        }
        guard snapshot.0, let format = snapshot.2, let tapInput = snapshot.3, let callbacks = snapshot.4 else { return }
        // Everything below sees only the tap's buffers, never the interface's inputs.
        guard let tapData = tapInput.tapBuffers(of: inputData),
              tapData.pointee.mNumberBuffers > 0,
              let frames = RecorderPCMBufferLayout.frameCount(
                  bufferList: tapData,
                  streamDescription: format.streamDescription.pointee
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: tapData, deallocator: nil)
        else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        buffer.frameLength = min(frames, buffer.frameCapacity)
        guard buffer.frameLength > 0 else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        let bytes = RecorderPCMBufferLayout.usableByteCount(bufferList: tapData)
        guard bytes > 0 else {
            callbacks.onStructuralNoData(snapshot.1)
            return
        }
        _ = callbacks.onPCM(snapshot.1, format, buffer, bytes)
    }

    private func installPropertyListeners(anchorDeviceID: AudioObjectID) throws {
        let system = AudioObjectID(kAudioObjectSystemObject)
        try throwIfMuteReleased()
        try addPropertyListener(
            objectID: system,
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try throwIfMuteReleased()
        try addPropertyListener(
            objectID: system,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try throwIfMuteReleased()
        try addPropertyListener(
            objectID: anchorDeviceID,
            selector: kAudioDevicePropertyNominalSampleRate,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try throwIfMuteReleased()
        try addPropertyListener(
            objectID: anchorDeviceID,
            selector: kAudioDevicePropertyDeviceIsAlive,
            scope: kAudioObjectPropertyScopeGlobal
        )
        try throwIfMuteReleased()
        try addPropertyListener(
            objectID: anchorDeviceID,
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput
        )
        // The device's input streams precede the tap in the aggregate's input list, so a
        // change there reshapes the list: rebuild with a freshly resolved layout.
        try throwIfMuteReleased()
        try addPropertyListener(
            objectID: anchorDeviceID,
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeInput
        )
    }

    private func addPropertyListener(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws {
        let address = AudioObjectPropertyAddress(
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
        let status = hal.addPropertyListener(objectID, address, listenerQueue, block)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not observe audio route property \(selector)")
        }
        propertyRegistrations.append(PropertyRegistration(objectID: objectID, address: address, block: block))
    }

    private func removePropertyListeners() {
        for registration in propertyRegistrations {
            hal.removePropertyListener(registration.objectID, registration.address, listenerQueue, registration.block)
        }
        propertyRegistrations.removeAll()
    }
}

/// Every HAL call a tap graph makes, injectable so tests can run the graph against a fake
/// and make any call hang.
struct SystemAudioTapHAL: Sendable {
    var createProcessTap: @Sendable (CATapDescription) -> (OSStatus, AudioObjectID)
    var destroyProcessTap: @Sendable (AudioObjectID) -> Void
    var readDefaultSystemOutputDevice: @Sendable () throws -> (id: AudioObjectID, uid: String)
    var createAggregateDevice: @Sendable ([String: Any]) -> (OSStatus, AudioObjectID)
    var destroyAggregateDevice: @Sendable (AudioObjectID) -> Void
    var readTapFormat: @Sendable (AudioObjectID) -> (OSStatus, AudioStreamBasicDescription)
    var readNominalSampleRate: @Sendable (AudioObjectID) -> (OSStatus, Double)
    /// Channels of each input stream, in IO-proc buffer order (kAudioDevicePropertyStreamConfiguration).
    var readInputStreamChannels: @Sendable (AudioObjectID) -> (OSStatus, [UInt32])
    var createIOProc: @Sendable (AudioObjectID, DispatchQueue, @escaping AudioDeviceIOBlock)
        -> (OSStatus, AudioDeviceIOProcID?)
    var destroyIOProc: @Sendable (AudioObjectID, AudioDeviceIOProcID) -> Void
    var startDevice: @Sendable (AudioObjectID, AudioDeviceIOProcID) -> OSStatus
    var stopDevice: @Sendable (AudioObjectID, AudioDeviceIOProcID) -> Void
    var addPropertyListener: @Sendable (
        AudioObjectID, AudioObjectPropertyAddress, DispatchQueue, @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus
    var removePropertyListener: @Sendable (
        AudioObjectID, AudioObjectPropertyAddress, DispatchQueue, @escaping AudioObjectPropertyListenerBlock
    ) -> Void

    static let live = SystemAudioTapHAL(
        createProcessTap: { description in
            var id = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &id)
            return (status, id)
        },
        destroyProcessTap: { _ = AudioHardwareDestroyProcessTap($0) },
        readDefaultSystemOutputDevice: { try LiveOutputDevice.readDefaultSystemOutputDevice() },
        createAggregateDevice: { description in
            var id = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
            return (status, id)
        },
        destroyAggregateDevice: { _ = AudioHardwareDestroyAggregateDevice($0) },
        readTapFormat: { tapID in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var description = AudioStreamBasicDescription()
            let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &description)
            return (status, description)
        },
        readNominalSampleRate: { deviceID in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var size = UInt32(MemoryLayout<Double>.size)
            var sampleRate: Double = 0
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
            return (status, sampleRate)
        },
        readInputStreamChannels: { deviceID in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
            guard status == noErr else { return (status, []) }
            // Room for the header plus as many AudioBuffers as the reported size can hold.
            let capacity = max(1, (Int(size) - MemoryLayout<AudioBufferList>.size) / MemoryLayout<AudioBuffer>.stride + 1)
            let list = AudioBufferList.allocate(maximumBuffers: capacity)
            defer { free(list.unsafeMutablePointer) }
            status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, list.unsafeMutablePointer)
            guard status == noErr else { return (status, []) }
            guard list.count <= capacity else { return (kAudioHardwareBadPropertySizeError, []) }
            return (noErr, list.map(\.mNumberChannels))
        },
        createIOProc: { deviceID, queue, block in
            var procID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue, block)
            return (status, procID)
        },
        destroyIOProc: { _ = AudioDeviceDestroyIOProcID($0, $1) },
        startDevice: { AudioDeviceStart($0, $1) },
        stopDevice: { _ = AudioDeviceStop($0, $1) },
        addPropertyListener: { objectID, address, queue, block in
            var address = address
            return AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
        },
        removePropertyListener: { objectID, address, queue, block in
            var address = address
            _ = AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
        }
    )
}

private enum LiveOutputDevice {
    static func readDefaultSystemOutputDevice() throws -> (id: AudioObjectID, uid: String) {
        do {
            return try readOutputDevice(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        } catch {
            return try readOutputDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        }
    }

    private static func readOutputDevice(selector: AudioObjectPropertySelector) throws -> (id: AudioObjectID, uid: String) {
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
}

/// The process tap's object ID, handed out for destruction exactly once.
final class ProcessTapObjectCell: @unchecked Sendable {
    private enum State {
        case empty
        case holding(AudioObjectID)
        case released
    }

    private let lock = NSLock()
    private var state = State.empty

    var isReleased: Bool {
        lock.withLock {
            if case .released = state { return true }
            return false
        }
    }

    /// False once the mute was released: the caller must destroy `id` itself.
    func publish(_ id: AudioObjectID) -> Bool {
        lock.withLock {
            if case .released = state { return false }
            state = .holding(id)
            return true
        }
    }

    /// The tap to destroy, if any. `permanently` also refuses every later `publish`.
    func take(permanently: Bool) -> AudioObjectID? {
        lock.withLock {
            let held: AudioObjectID?
            if case .holding(let id) = state { held = id } else { held = nil }
            if permanently {
                state = .released
            } else if held != nil {
                state = .empty
            }
            return held
        }
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
