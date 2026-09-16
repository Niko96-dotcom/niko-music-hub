import AppCore
import AVFAudio
import Combine
import XCTest
@testable import FeatureAudioRecorder

@MainActor
final class AudioRecorderViewModelTests: XCTestCase {
    func testStartingStatePersistsUntilCaptureReadiness() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-starting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let startEntered = expectation(description: "capture start entered")
        let port = ReadinessControlledCapturePort(onStart: { startEntered.fulfill() })
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: directory,
            outputInboxStore: InMemoryOutputInboxStore()
        )
        let recording = expectation(description: "recording only after readiness")
        var cancellable: AnyCancellable?
        cancellable = vm.$recordingState.sink { state in
            if state == .recording { recording.fulfill() }
        }

        await vm.startRecording()
        XCTAssertEqual(vm.recordingState, .starting)
        XCTAssertNil(vm.currentLevel)

        await fulfillment(of: [startEntered], timeout: 1)
        port.completeHealthyStart()
        await fulfillment(of: [recording], timeout: 1)
        XCTAssertEqual(vm.recordingState, .recording)
        await vm.stopRecording()
        cancellable?.cancel()
    }

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

    func testInitialMaxDurationMinutesSeededFromSettingsValue() {
        let port = MockAudioCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let outputInboxStore = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: useCase,
            outputURL: URL(fileURLWithPath: "/tmp"),
            outputInboxStore: outputInboxStore,
            initialMaxDurationMinutes: 90
        )

        XCTAssertEqual(vm.maxDurationMinutes, 90)
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

    func testInboxAddFailureKeepsRecordingSuccessWithWarning() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-vm-handoff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = WritingCapturePort(writesAudioFrames: true)
        let inbox = ThrowingOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: inbox
        )

        await vm.startRecording()
        try await waitUntilRecording(port)
        await vm.stopRecording()

        let recordedURL = try XCTUnwrap(vm.lastRecordedURL)
        XCTAssertEqual(vm.recordingState, .idle)
        XCTAssertTrue(vm.showSaveConfirmation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedURL.path))
        XCTAssertTrue(vm.handoffWarningMessage?.contains("Output Inbox") == true)
    }

    func testStartRecordingCreatesMissingOutputDirectoryAndAddsInboxItem() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-missing-parent-\(UUID().uuidString)", isDirectory: true)
        let missingOutputDirectory = tempRoot.appendingPathComponent("Nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let port = WritingCapturePort(writesAudioFrames: true)
        let inbox = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: missingOutputDirectory,
            outputInboxStore: inbox
        )

        await vm.startRecording()
        try await waitUntil { port.recording }
        await vm.stopRecording()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingOutputDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(vm.recordingState, .idle)
        XCTAssertEqual(try inbox.listItems().count, 1)
        XCTAssertEqual(vm.lastRecordedURL?.pathExtension.lowercased(), "wav")
    }

    func testNaturalStreamEndFinalizesRecordingThroughViewModel() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-natural-end-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = NaturalEndCapturePort()
        let inbox = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: inbox
        )

        await vm.startRecording()
        try await waitUntil { vm.showSaveConfirmation }

        XCTAssertEqual(port.stopCallCount, 1)
        XCTAssertEqual(vm.recordingState, .idle)
        XCTAssertEqual(try inbox.listItems().count, 1)
        XCTAssertNotNil(vm.lastRecordedURL)
    }

    func testMaxDurationAutoFinishFinalizesWAVAndInboxItem() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-max-duration-deterministic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = NaturalEndCapturePort()
        let inbox = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: inbox
        )
        vm.maxDurationMinutes = 1

        await vm.startRecording()
        try await waitUntil { vm.showSaveConfirmation }

        let receivedMaxDuration = try XCTUnwrap(port.receivedMaxDuration)
        XCTAssertEqual(receivedMaxDuration, 60, accuracy: 0.001)
        XCTAssertEqual(port.stopCallCount, 1)
        XCTAssertEqual(vm.recordingState, .idle)
        let recordedURL = try XCTUnwrap(vm.lastRecordedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedURL.path))
        XCTAssertEqual(recordedURL.pathExtension.lowercased(), "wav")
        let item = try XCTUnwrap(try inbox.listItems().first)
        XCTAssertEqual(item.sourceToolID.rawValue, "audio-recorder")
        XCTAssertEqual(item.status, .available)
        XCTAssertEqual(item.fileURL.standardizedFileURL, recordedURL.standardizedFileURL)
    }

    func testDuplicateStartsOnlyStartCaptureOnce() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-duplicate-start-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = DelayedStartCapturePort()
        let inbox = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: inbox
        )

        async let first: Void = vm.startRecording()
        async let second: Void = vm.startRecording()
        _ = await (first, second)

        try await waitUntil { port.startRecordingCallCount == 1 }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(port.startRecordingCallCount, 1)

        await vm.stopRecording()
    }

    func testStopErrorClearsRecordingStateAndPublishesError() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-stop-error-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = StopFailingOnceCapturePort()
        let inbox = InMemoryOutputInboxStore()
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: inbox
        )

        await vm.startRecording()
        try await waitUntil { port.recording }
        await vm.stopRecording()

        XCTAssertEqual(vm.recordingState, .error(.apiError("forced stop failure")))
        XCTAssertFalse(vm.isRecording)
        XCTAssertEqual(try inbox.listItems().count, 0)

        await vm.startRecording()
        try await waitUntil { port.startRecordingCallCount == 2 }
        try await waitUntil { port.recording }
        await vm.stopRecording()
        XCTAssertEqual(vm.recordingState, .idle)
    }

    func testNoAudioCapturedMapsToPermissionNeeded() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-vm-no-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = WritingCapturePort(writesAudioFrames: false, inputFrameCount: 0)
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

        XCTAssertEqual(vm.recordingState, .permissionNeeded)
        if case .error = vm.recordingState {
            XCTFail("Expected .permissionNeeded, not .error")
        }
        XCTAssertEqual(try inbox.listItems().count, 0)
    }

    func testPermissionClassAPIErrorMapsToPermissionNeeded() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-vm-tcc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = StartFailingCapturePort(
            error: .apiError("AudioDeviceStart not authorized (TCC)")
        )
        let vm = AudioRecorderViewModel(
            capturePort: port,
            useCase: RecordSystemAudioUseCase(capturePort: port),
            outputURL: tempDir,
            outputInboxStore: InMemoryOutputInboxStore()
        )

        await vm.startRecording()
        try await waitUntil { vm.recordingState == .permissionNeeded }

        XCTAssertEqual(vm.recordingState, .permissionNeeded)
    }

    func testPresentationMapsNoAudioAndPermissionClassErrors() {
        XCTAssertEqual(
            RecordingDisplayState.presentation(for: .noAudioCaptured("no frames")),
            .permissionNeeded
        )
        XCTAssertEqual(
            RecordingDisplayState.presentation(for: .apiError("not authorized to capture system audio")),
            .permissionNeeded
        )
        XCTAssertEqual(
            RecordingDisplayState.presentation(for: .permissionDenied),
            .permissionNeeded
        )
        XCTAssertEqual(
            RecordingDisplayState.presentation(for: .apiError("forced stop failure")),
            .error(.apiError("forced stop failure"))
        )
        XCTAssertEqual(
            RecordingDisplayState.presentation(for: .writeError("disk full")),
            .error(.writeError("disk full"))
        )
        XCTAssertEqual(
            RecordingDisplayState.presentation(for: .verificationFailed("Recording contained no audio frames.")),
            .error(.verificationFailed("Recording contained no audio frames."))
        )
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

    func testStopRecordingRejectsResultsWithWriteErrors() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-vm-write-errors-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let port = WritingCapturePort(writesAudioFrames: true, writeErrorCount: 2)
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

        guard case .error(.writeError(let message)) = vm.recordingState else {
            XCTFail("Expected writeError, got \(vm.recordingState)")
            return
        }
        XCTAssertTrue(message.contains("write failed"))
        XCTAssertTrue(message.contains("writeErrors=2") || message.contains("2 errors"))
        XCTAssertEqual(try inbox.listItems().count, 0)
        if let recorded = port.recordedOutputURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: recorded.path))
        }
    }

    func testFailedVerificationRemovesIncompleteOutput() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-vm-remove-failed-\(UUID().uuidString)", isDirectory: true)
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
        try await waitUntil { port.recording }
        await vm.stopRecording()

        let failedURL = try XCTUnwrap(port.recordedOutputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedURL.path))
        XCTAssertEqual(try inbox.listItems().count, 0)
    }
}

private func waitUntilRecording(_ port: WritingCapturePort) async throws {
    try await waitUntil { port.recording }
}

private func waitUntil(
    timeoutAttempts: Int = 50,
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<timeoutAttempts {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for condition")
}

private func legacyWaitUntilRecording(_ port: WritingCapturePort) async throws {
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

private final class StartFailingCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false
    private let error: RecorderError

    init(error: RecorderError) {
        self.error = error
    }

    func checkPermission() async -> RecorderPermissionState { .authorized }
    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        throw error
    }

    func stopRecording() async throws -> RecorderResult {
        throw RecorderError.apiError("No active recording")
    }
}

private final class WritingCapturePort: AudioCapturePort, @unchecked Sendable {
    private let writesAudioFrames: Bool
    private let writeErrorCount: Int
    private let inputFrameCount: Int64
    private var continuation: AsyncStream<RecorderAudioLevel>.Continuation?
    private var outputURL: URL?
    var recordedOutputURL: URL? { outputURL }
    var recording: Bool = false

    init(writesAudioFrames: Bool, writeErrorCount: Int = 0, inputFrameCount: Int64 = 1024) {
        self.writesAudioFrames = writesAudioFrames
        self.writeErrorCount = writeErrorCount
        self.inputFrameCount = inputFrameCount
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
        var file: AVAudioFile? = try AVAudioFile(forWriting: outputURL, settings: settings)
        if writesAudioFrames {
            let format = try XCTUnwrap(file?.processingFormat)
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
            try file!.write(from: buffer)
        }
        // AVAudioFile finalizes its WAV header when released. Drop the last
        // writer reference before AudioRecorderViewModel verifies/reopens it so
        // this fixture is independent of ARC lifetime optimization.
        file = nil

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
                inputFrameCount: inputFrameCount,
                convertedFrameCount: writesAudioFrames ? 512 : 0,
                writtenFrameCount: writesAudioFrames ? 512 : 0,
                writeErrorCount: writeErrorCount
            )
        )
    }
}

private final class ReadinessControlledCapturePort: AudioCapturePort, @unchecked Sendable {
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<AsyncStream<RecorderAudioLevel>, any Error>?
    private var levelContinuation: AsyncStream<RecorderAudioLevel>.Continuation?
    private var outputURL: URL?
    private var _recording = false
    private let onStart: @Sendable () -> Void

    init(onStart: @escaping @Sendable () -> Void) {
        self.onStart = onStart
    }

    var recording: Bool { lock.withLock { _recording } }
    func checkPermission() async -> RecorderPermissionState { .authorized }
    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }

    func startRecording(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?
    ) async throws -> AsyncStream<RecorderAudioLevel> {
        lock.withLock { self.outputURL = outputURL }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { startContinuation = continuation }
            onStart()
        }
    }

    func completeHealthyStart() {
        let stream = AsyncStream<RecorderAudioLevel> { continuation in
            lock.withLock { levelContinuation = continuation }
            continuation.yield(RecorderAudioLevel(peak: 0, average: 0, elapsedTime: 0.01))
        }
        let pending = lock.withLock { () -> CheckedContinuation<AsyncStream<RecorderAudioLevel>, any Error>? in
            _recording = true
            let value = startContinuation
            startContinuation = nil
            return value
        }
        pending?.resume(returning: stream)
    }

    func stopRecording() async throws -> RecorderResult {
        guard let url = lock.withLock({ outputURL }) else {
            throw RecorderError.apiError("Missing output URL")
        }
        try NaturalEndCapturePort.writeValidWAV(to: url)
        lock.withLock { _recording = false }
        levelContinuation?.finish()
        return RecorderResult(
            outputURL: url,
            duration: 0.1,
            sampleRate: 44_100,
            bitDepth: 24,
            channelCount: 2,
            frameCount: 512
        )
    }
}

private final class NaturalEndCapturePort: AudioCapturePort, @unchecked Sendable {
    private var outputURL: URL?
    var recording = false
    var stopCallCount = 0
    var receivedMaxDuration: TimeInterval?

    func checkPermission() async -> RecorderPermissionState { .authorized }
    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        self.outputURL = outputURL
        receivedMaxDuration = maxDuration
        recording = true
        return AsyncStream { continuation in
            Task {
                continuation.yield(RecorderAudioLevel(peak: 0.4, average: 0.2, elapsedTime: 0.1))
                try? await Task.sleep(for: .milliseconds(10))
                continuation.finish()
            }
        }
    }

    func stopRecording() async throws -> RecorderResult {
        stopCallCount += 1
        recording = false
        return try writeValidRecording()
    }

    private func writeValidRecording() throws -> RecorderResult {
        guard let outputURL else {
            throw RecorderError.apiError("Missing output URL")
        }
        try Self.writeValidWAV(to: outputURL)
        return RecorderResult(outputURL: outputURL, duration: 0.1, sampleRate: 44_100, bitDepth: 24, channelCount: 2, frameCount: 512)
    }

    static func writeValidWAV(to outputURL: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: outputURL, settings: settings)
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
}

private final class DelayedStartCapturePort: AudioCapturePort, @unchecked Sendable {
    private var continuation: AsyncStream<RecorderAudioLevel>.Continuation?
    private var outputURL: URL?
    var recording = false
    var startRecordingCallCount = 0

    func checkPermission() async -> RecorderPermissionState {
        try? await Task.sleep(for: .milliseconds(50))
        return .authorized
    }

    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        startRecordingCallCount += 1
        self.outputURL = outputURL
        recording = true
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(RecorderAudioLevel(peak: 0.2, average: 0.1, elapsedTime: 0.1))
        }
    }

    func stopRecording() async throws -> RecorderResult {
        guard let outputURL else {
            throw RecorderError.apiError("Missing output URL")
        }
        try NaturalEndCapturePort.writeValidWAV(to: outputURL)
        recording = false
        continuation?.finish()
        return RecorderResult(outputURL: outputURL, duration: 0.1, sampleRate: 44_100, bitDepth: 24, channelCount: 2, frameCount: 512)
    }
}

private final class StopFailingOnceCapturePort: AudioCapturePort, @unchecked Sendable {
    private var continuation: AsyncStream<RecorderAudioLevel>.Continuation?
    private var outputURL: URL?
    private var shouldFailStop = true
    var recording = false
    var startRecordingCallCount = 0

    func checkPermission() async -> RecorderPermissionState { .authorized }
    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        startRecordingCallCount += 1
        self.outputURL = outputURL
        recording = true
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(RecorderAudioLevel(peak: 0.3, average: 0.2, elapsedTime: 0.1))
        }
    }

    func stopRecording() async throws -> RecorderResult {
        guard let outputURL else {
            throw RecorderError.apiError("Missing output URL")
        }
        recording = false
        continuation?.finish()
        if shouldFailStop {
            shouldFailStop = false
            throw RecorderError.apiError("forced stop failure")
        }
        try NaturalEndCapturePort.writeValidWAV(to: outputURL)
        return RecorderResult(outputURL: outputURL, duration: 0.1, sampleRate: 44_100, bitDepth: 24, channelCount: 2, frameCount: 512)
    }
}

private final class InMemoryOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private var items: [OutputInboxItem] = []

    func listItems() throws -> [OutputInboxItem] { items }
    func addItem(_ item: OutputInboxItem) throws { items.append(item) }
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct ThrowingOutputInboxStore: OutputInboxStore {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {
        throw FixtureOutputInboxError.forced
    }
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private enum FixtureOutputInboxError: LocalizedError {
    case forced

    var errorDescription: String? {
        "forced inbox failure"
    }
}
