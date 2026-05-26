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

/// Manages a Core Audio process tap + private aggregate device for system-wide capture (macOS 14.2+).
final class SystemAudioProcessTapSession: @unchecked Sendable {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var writer: WAVRecorderWriter?
    private var levelHandler: ((RecorderAudioLevel) -> Void)?
    private var maxDuration: TimeInterval?
    private var recordingStart: Date?
    private let ioQueue = DispatchQueue(label: "NikoMusicHub.SystemAudioProcessTapSession.io", qos: .userInitiated)
    private var diagnostics = RecorderDiagnosticsAccumulator()
    private let stateLock = NSLock()
    private var isRunning = false

    deinit {
        tearDown()
    }

    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping (RecorderAudioLevel) -> Void
    ) throws {
        guard !isRunning else {
            throw RecorderError.apiError("Recording session already active")
        }

        levelHandler = onLevel
        self.maxDuration = maxDuration
        recordingStart = Date()

        let processTap = try createProcessTap()
        tapID = processTap.id
        let outputDeviceUID = try readDefaultSystemOutputDeviceUID()
        let tapUID = processTap.uid
        aggregateDeviceID = try createAggregateDevice(tapUID: tapUID, outputDeviceUID: outputDeviceUID)
        try attachTapToAggregateDevice(tapUID: tapUID, aggregateDeviceID: aggregateDeviceID)

        let streamDescription = try readTapStreamDescription(tapID: tapID)
        guard let tapAudioFormat = AVAudioFormat(streamDescription: streamDescription) else {
            throw RecorderError.apiError("Unsupported tap audio format")
        }

        let activeWriter = try WAVRecorderWriter(outputURL: outputURL, preset: preset)
        let destinationFormat = activeWriter.processingFormat

        tapFormat = tapAudioFormat
        outputFormat = destinationFormat
        converter = AVAudioConverter(from: tapAudioFormat, to: destinationFormat)
        writer = activeWriter
        diagnostics = RecorderDiagnosticsAccumulator(
            outputDeviceUID: outputDeviceUID,
            tapSampleRate: tapAudioFormat.sampleRate,
            tapChannelCount: Int(tapAudioFormat.channelCount)
        )

        isRunning = true
        try installIOProc(deviceID: aggregateDeviceID)
        try startDevice(deviceID: aggregateDeviceID)
    }

    func stop() throws -> RecorderResult {
        guard isRunning else {
            throw RecorderError.apiError("No active recording")
        }

        stopIODeviceOnly()
        isRunning = false

        guard let activeWriter = writer else {
            throw RecorderError.writeError("Recorder writer not initialized")
        }

        diagnostics.setWrittenFrameCount(activeWriter.writtenFrameCount)
        let result = try activeWriter.finalize(diagnostics: diagnostics.snapshot())
        self.writer = nil
        converter = nil
        tapFormat = nil
        outputFormat = nil
        levelHandler = nil
        maxDuration = nil
        recordingStart = nil

        destroyTapAndAggregate()
        return result
    }

    private func tearDown() {
        stopIODeviceOnly()
        destroyTapAndAggregate()
        isRunning = false
    }

    private func stopIODeviceOnly() {
        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
    }

    private func destroyTapAndAggregate() {
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
    }

    private func createProcessTap() throws -> (id: AudioObjectID, uid: String) {
        let description = SystemAudioTapConfiguration.makeGlobalTapDescription()
        description.uuid = UUID()

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create system audio tap")
        }
        return (tapID, description.uuid.uuidString)
    }

    private func createAggregateDevice(tapUID: String, outputDeviceUID mainDeviceUID: String) throws -> AudioObjectID {
        let description = SystemAudioTapConfiguration.makeAggregateDeviceDescription(
            tapUID: tapUID,
            outputDeviceUID: mainDeviceUID
        )

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create aggregate device")
        }
        return deviceID
    }

    private func attachTapToAggregateDevice(tapUID: String, aggregateDeviceID: AudioObjectID) throws {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var tapList = [tapUID] as CFArray
        let propertySize = UInt32(MemoryLayout<CFArray>.size)
        let status = withUnsafeMutablePointer(to: &tapList) { tapListPointer in
            AudioObjectSetPropertyData(
                aggregateDeviceID,
                &propertyAddress,
                0,
                nil,
                propertySize,
                tapListPointer
            )
        }
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not attach tap to aggregate device")
        }
    }

    private func readTapStreamDescription(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var streamDescription = AudioStreamBasicDescription()
        let status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, &streamDescription)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read tap format")
        }
        return streamDescription
    }

    private func readDefaultSystemOutputDeviceUID() throws -> String {
        do {
            return try readOutputDeviceUID(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        } catch {
            return try readOutputDeviceUID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        }
    }

    private func readOutputDeviceUID(selector: AudioObjectPropertySelector) throws -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read output device")
        }

        var uid = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = withUnsafeMutablePointer(to: &uid) { uidPtr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, uidPtr)
        }
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read output device UID")
        }
        return uid as String
    }

    private func installIOProc(deviceID: AudioObjectID) throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, ioQueue) { [weak self] _, inputData, _, outputData, _ in
            if inputData.pointee.mNumberBuffers > 0 {
                self?.diagnostics.recordIOCallback(source: .input)
                self?.handleAudio(bufferList: inputData)
            } else {
                self?.diagnostics.recordIOCallback(source: .output)
                self?.handleAudio(bufferList: UnsafePointer(outputData))
            }
        }
        guard status == noErr, let procID else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create IO proc")
        }
        ioProcID = procID
    }

    private func startDevice(deviceID: AudioObjectID) throws {
        guard let ioProcID else {
            throw RecorderError.apiError("IO proc not installed")
        }
        let status = AudioDeviceStart(deviceID, ioProcID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not start aggregate device")
        }
    }

    private func handleAudio(bufferList inputData: UnsafePointer<AudioBufferList>?) {
        stateLock.lock()
        guard isRunning,
              let writer,
              let tapFormat,
              let outputFormat,
              let converter,
              let inputData
        else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let bufferList = inputData.pointee
        guard bufferList.mNumberBuffers > 0 else {
            diagnostics.recordZeroBuffer()
            return
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: inputData, deallocator: nil) else {
            diagnostics.recordZeroBuffer()
            return
        }
        diagnostics.recordInputFrames(Int64(inputBuffer.frameLength))

        let frameCapacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * outputFormat.sampleRate / tapFormat.sampleRate
        ) + 32
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            diagnostics.recordZeroBuffer()
            return
        }

        var error: NSError?
        let inputState = ConverterInputState()
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            guard !inputState.didProvideInput else {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputState.didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        if error != nil {
            diagnostics.recordConverterError()
            return
        }
        if convertedBuffer.frameLength == 0 {
            diagnostics.recordZeroBuffer()
            return
        }
        diagnostics.recordConvertedFrames(Int64(convertedBuffer.frameLength))

        do {
            try writer.writeBuffer(convertedBuffer)
        } catch {
            diagnostics.recordWriteError()
            return
        }
        diagnostics.setWrittenFrameCount(writer.writtenFrameCount)

        let peak = meterPeak(from: inputBuffer)
        let average = peak * 0.6
        let elapsed = writer.currentTime
        let level = RecorderAudioLevel(peak: peak, average: average, elapsedTime: elapsed)
        levelHandler?(level)

        if let maxDuration, elapsed >= maxDuration {
            stateLock.lock()
            isRunning = false
            stateLock.unlock()
            if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
            }
        }
    }

    private func meterPeak(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard frames > 0, channels > 0 else { return 0 }

        var peak: Float = 0
        for channel in 0..<channels {
            for frame in 0..<frames {
                peak = max(peak, abs(channelData[channel][frame]))
            }
        }
        return min(peak, 1.0)
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var didProvideInput = false
}

private final class RecorderDiagnosticsAccumulator: @unchecked Sendable {
    enum CallbackSource {
        case input
        case output
    }

    private let lock = NSLock()
    private var outputDeviceUID: String
    private var tapSampleRate: Double
    private var tapChannelCount: Int
    private var ioCallbackCount = 0
    private var inputBufferCallbackCount = 0
    private var outputBufferCallbackCount = 0
    private var zeroBufferCallbackCount = 0
    private var inputFrameCount: Int64 = 0
    private var convertedFrameCount: Int64 = 0
    private var writtenFrameCount: Int64 = 0
    private var converterErrorCount = 0
    private var writeErrorCount = 0

    init(
        outputDeviceUID: String = "",
        tapSampleRate: Double = 0,
        tapChannelCount: Int = 0
    ) {
        self.outputDeviceUID = outputDeviceUID
        self.tapSampleRate = tapSampleRate
        self.tapChannelCount = tapChannelCount
    }

    func recordIOCallback(source: CallbackSource) {
        lock.lock()
        ioCallbackCount += 1
        switch source {
        case .input:
            inputBufferCallbackCount += 1
        case .output:
            outputBufferCallbackCount += 1
        }
        lock.unlock()
    }

    func recordZeroBuffer() {
        lock.lock()
        zeroBufferCallbackCount += 1
        lock.unlock()
    }

    func recordInputFrames(_ frames: Int64) {
        lock.lock()
        inputFrameCount += max(0, frames)
        lock.unlock()
    }

    func recordConvertedFrames(_ frames: Int64) {
        lock.lock()
        convertedFrameCount += max(0, frames)
        lock.unlock()
    }

    func setWrittenFrameCount(_ frames: Int64) {
        lock.lock()
        writtenFrameCount = max(0, frames)
        lock.unlock()
    }

    func recordConverterError() {
        lock.lock()
        converterErrorCount += 1
        lock.unlock()
    }

    func recordWriteError() {
        lock.lock()
        writeErrorCount += 1
        lock.unlock()
    }

    func snapshot() -> RecorderDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return RecorderDiagnostics(
            outputDeviceUID: outputDeviceUID,
            tapSampleRate: tapSampleRate,
            tapChannelCount: tapChannelCount,
            ioCallbackCount: ioCallbackCount,
            inputBufferCallbackCount: inputBufferCallbackCount,
            outputBufferCallbackCount: outputBufferCallbackCount,
            zeroBufferCallbackCount: zeroBufferCallbackCount,
            inputFrameCount: inputFrameCount,
            convertedFrameCount: convertedFrameCount,
            writtenFrameCount: writtenFrameCount,
            converterErrorCount: converterErrorCount,
            writeErrorCount: writeErrorCount
        )
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
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ] as CFArray,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ] as CFArray,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false
        ]
    }
}

private extension AVAudioFormat {
    convenience init?(streamDescription: AudioStreamBasicDescription) {
        var description = streamDescription
        self.init(streamDescription: &description)
    }
}
