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

        tapID = try createProcessTap()
        aggregateDeviceID = try createAggregateDevice(tapUID: try readTapUID(tapID: tapID))

        let streamDescription = try readTapStreamDescription(tapID: tapID)
        guard let tapAudioFormat = AVAudioFormat(streamDescription: streamDescription) else {
            throw RecorderError.apiError("Unsupported tap audio format")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: preset.sampleRate,
            AVNumberOfChannelsKey: preset.channelCount,
            AVLinearPCMBitDepthKey: preset.bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let destinationFormat = AVAudioFormat(settings: settings) else {
            throw RecorderError.apiError("Could not build output audio format")
        }

        tapFormat = tapAudioFormat
        outputFormat = destinationFormat
        converter = AVAudioConverter(from: tapAudioFormat, to: destinationFormat)
        writer = try WAVRecorderWriter(outputURL: outputURL, preset: preset)

        try installIOProc(deviceID: aggregateDeviceID)
        try startDevice(deviceID: aggregateDeviceID)
        isRunning = true
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

        let result = try activeWriter.finalize()
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

    private func createProcessTap() throws -> AudioObjectID {
        let description = CATapDescription()
        description.name = "OutsideCubaseHub-SystemTap"
        description.processes = []
        description.isPrivate = true
        description.isMixdown = true
        description.isMono = false
        description.isExclusive = false
        description.stream = 0
        description.muteBehavior = CATapMuteBehavior.unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create system audio tap")
        }
        return tapID
    }

    private func createAggregateDevice(tapUID: String) throws -> AudioObjectID {
        let uid = UUID().uuidString
        var mainDeviceUID = ""
        if let defaultUID = try? readDefaultOutputDeviceUID() {
            mainDeviceUID = defaultUID
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OutsideCubaseHub-Aggregate",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
            kAudioAggregateDeviceMainSubDeviceKey: mainDeviceUID,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ] as CFArray,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false
        ]

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not create aggregate device")
        }
        return deviceID
    }

    private func readTapUID(tapID: AudioObjectID) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var tapUID = "" as CFString
        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { uidPtr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, uidPtr)
        }
        guard uidStatus == noErr else {
            throw SystemAudioTapError.osStatus(uidStatus, context: "Could not read tap UID")
        }
        return tapUID as String
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

    private func readDefaultOutputDeviceUID() throws -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID)
        guard status == noErr else {
            throw SystemAudioTapError.osStatus(status, context: "Could not read default output device")
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
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil) { [weak self] _, inputData, _, _, _ in
            self?.handleInput(inputData: inputData)
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

    private func handleInput(inputData: UnsafePointer<AudioBufferList>?) {
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
        guard bufferList.mNumberBuffers > 0 else { return }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: inputData, deallocator: nil) else {
            return
        }

        let frameCapacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * outputFormat.sampleRate / tapFormat.sampleRate
        ) + 32
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        if error != nil { return }
        if convertedBuffer.frameLength == 0 { return }

        do {
            try writer.writeBuffer(convertedBuffer)
        } catch {
            return
        }

        let peak = meterPeak(from: convertedBuffer)
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

private extension AVAudioFormat {
    convenience init?(streamDescription: AudioStreamBasicDescription) {
        var description = streamDescription
        self.init(streamDescription: &description)
    }
}
