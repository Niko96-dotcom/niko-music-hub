import AppCore
import AVFAudio
import XCTest
@testable import FeatureAudioRecorder

@MainActor
final class AudioRecorderViewModelTests: XCTestCase {
    func testStartRecordingWhenPermissionDenied() async throws {
        let port = DenyingCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        await vm.startRecording()

        if case .permissionNeeded = vm.recordingState {
            // pass
        } else {
            XCTFail("Expected .permissionNeeded but got \(vm.recordingState)")
        }
    }

    func testStartRecordingWhenIncompatibleMacOS() async throws {
        let port = IncompatibleCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        await vm.startRecording()

        if case .incompatibleMacOS = vm.recordingState {
            // pass
        } else {
            XCTFail("Expected .incompatibleMacOS but got \(vm.recordingState)")
        }
    }

    func testFilenameOverridePassedToUseCase() async throws {
        let port = MockAudioCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        vm.filenameOverride = "My Recording.wav"
        XCTAssertEqual(vm.filenameOverride, "My Recording.wav")
    }

    func testMaxDurationPassedToUseCase() async throws {
        let port = MockAudioCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore
        )

        vm.maxDurationMinutes = 5
        XCTAssertEqual(vm.maxDurationMinutes, 5)
    }

    func testStopRecordingFinalizesAndAddsOutputInboxItem() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = WritingCapturePort(writesAudioFrames: true)
        let inbox = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: inbox
        )

        await vm.startRecording()
        try await waitUntilRecording(port)
        await vm.stopRecording()

        XCTAssertEqual(vm.recordingState, .idle)
        XCTAssertEqual(try inbox.listItems().count, 1)
        XCTAssertNotNil(vm.lastRecordedURL)
        XCTAssertTrue(vm.showSaveConfirmation)
    }

    func testStopRecordingRejectsEmptyWAVHeader() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-vm-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = WritingCapturePort(writesAudioFrames: false)
        let inbox = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: inbox
        )

        await vm.startRecording()
        try await waitUntilRecording(port)
        await vm.stopRecording()

        guard case .error(.verificationFailed(let message)) = vm.recordingState else {
            XCTFail("Expected verification failure, got \(vm.recordingState)")
            return
        }
        XCTAssertTrue(message.hasPrefix("Recording contained no audio frames."))
        XCTAssertTrue(message.contains("callbacks=3"))
        XCTAssertTrue(message.contains("inputFrames=1024"))
        XCTAssertTrue(message.contains("writtenFrames=0"))
        XCTAssertEqual(try inbox.listItems().count, 0)
    }
}

private func waitUntilRecording(_ port: WritingCapturePort) async throws {
    for _ in 0..<20 {
        if port.recording { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for mock recorder to start")
}

private final class DenyingCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .denied(needsSettings: true)
    }

    func requestPermission() async -> RecorderPermissionState {
        .denied(needsSettings: true)
    }

    func isCompatibleMacOS() -> Bool {
        true
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { _ in }
    }

    func stopRecording() async throws -> RecorderResult {
        RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}

private final class IncompatibleCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .authorized
    }

    func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    func isCompatibleMacOS() -> Bool {
        false
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { _ in }
    }

    func stopRecording() async throws -> RecorderResult {
        RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}

private final class MockAudioCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .authorized
    }

    func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    func isCompatibleMacOS() -> Bool {
        true
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                continuation.finish()
            }
        }
    }

    func stopRecording() async throws -> RecorderResult {
        RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0.1, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}

private final class WritingCapturePort: AudioCapturePort, @unchecked Sendable {
    private let writesAudioFrames: Bool
    private var continuation: AsyncStream<RecorderAudioLevel>.Continuation?
    private var outputURL: URL?
    var recording: Bool = false

    init(writesAudioFrames: Bool) {
        self.writesAudioFrames = writesAudioFrames
    }

    func checkPermission() async -> RecorderPermissionState {
        .authorized
    }

    func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    func isCompatibleMacOS() -> Bool {
        true
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        recording = true
        self.outputURL = outputURL
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(RecorderAudioLevel(peak: 0.5, average: 0.25, elapsedTime: 0.1))
        }
    }

    func stopRecording() async throws -> RecorderResult {
        guard let outputURL else {
            throw RecorderError.apiError("Missing output URL")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: outputURL, settings: settings)
        if writesAudioFrames {
            let format = file.processingFormat
            let frameCount: AVAudioFrameCount = 512
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            if let channelData = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(frameCount) {
                        channelData[channel][frame] = Float(frame % 32) / 32.0
                    }
                }
            }
            try file.write(from: buffer)
        }

        recording = false
        continuation?.finish()
        return RecorderResult(
            outputURL: outputURL,
            duration: writesAudioFrames ? 0.1 : 0,
            sampleRate: 44_100,
            bitDepth: 24,
            channelCount: 2,
            frameCount: writesAudioFrames ? 512 : 0,
            diagnostics: RecorderDiagnostics(
                outputDeviceUID: "test-output",
                tapSampleRate: 44_100,
                tapChannelCount: 2,
                ioCallbackCount: 3,
                inputBufferCallbackCount: 3,
                inputFrameCount: 1024,
                convertedFrameCount: writesAudioFrames ? 512 : 0,
                writtenFrameCount: writesAudioFrames ? 512 : 0
            )
        )
    }
}

private final class InMemoryOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private var items: [OutputInboxItem] = []

    func listItems() throws -> [OutputInboxItem] { items }
    func addItem(_ item: OutputInboxItem) throws { items.append(item) }
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}
