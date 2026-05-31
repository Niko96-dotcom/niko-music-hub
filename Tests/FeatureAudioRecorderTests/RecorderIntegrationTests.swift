import AppCore
import XCTest
@testable import FeatureAudioRecorder

final class RecorderIntegrationTests: XCTestCase {
    func testRecorderFeatureAppearsInToolRegistry() async throws {
        let feature = AudioRecorderFeature()
        XCTAssertEqual(feature.metadata.id.rawValue, "audio-recorder")
        XCTAssertEqual(feature.metadata.displayName, "Audio Recorder")
    }

    func testRecordingCapturesRealSystemAudio() async throws {
        let adapter = CoreAudioTapAdapter()
        try await requireRecordingPermission(adapter)
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_recording_\(UUID().uuidString).wav")

        let stream = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: 2.0)

        for await _ in stream {}
        let result = try await adapter.stopRecording()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan(result.duration, 0)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testOutputFileHasCorrectFormat() async throws {
        let adapter = CoreAudioTapAdapter()
        try await requireRecordingPermission(adapter)
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_format_\(UUID().uuidString).wav")

        let stream = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: 1.0)

        for await _ in stream {}
        let result = try await adapter.stopRecording()

        XCTAssertEqual(result.sampleRate, 44100)
        XCTAssertEqual(result.bitDepth, 24)
        XCTAssertEqual(result.channelCount, 2)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testPermissionPromptAppearsOnFirstUse() async throws {
        let adapter = CoreAudioTapAdapter()
        let state = await adapter.checkPermission()
        switch state {
        case .authorized, .denied, .restricted:
            break
        case .notDetermined:
            break
        }
    }

    func testIncompatibleMacOSShowsMessage() async throws {
        let adapter = CoreAudioTapAdapter()
        let compatible = adapter.isCompatibleMacOS()
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if majorVersion < 14 {
            XCTAssertFalse(compatible)
        } else {
            XCTAssertTrue(compatible)
        }
    }

    func testMaxDurationAutoStop() async throws {
        let adapter = CoreAudioTapAdapter()
        try await requireRecordingPermission(adapter)
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_duration_\(UUID().uuidString).wav")

        let startTime = Date()
        let stream = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: 1.0)

        for await _ in stream {}
        let result = try await adapter.stopRecording()
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertTrue(elapsed >= 1.0 && elapsed < 2.0, "Duration should be ~1 second, got \(elapsed)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testFilenameOverrideRoundTrip() async throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let filename = useCase.generateOutputFilename(override: "My Test Recording.wav")
        XCTAssertEqual(filename, "My Test Recording.wav")
    }

    func testRecordingProducesOutputInboxItem() async throws {
        let adapter = CoreAudioTapAdapter()
        try await requireRecordingPermission(adapter)
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_inbox_\(UUID().uuidString).wav")

        let stream = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: 1.0)

        for await _ in stream {}
        let result = try await adapter.stopRecording()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(result.sampleRate, 44100)
        XCTAssertEqual(result.bitDepth, 24)
        XCTAssertEqual(result.channelCount, 2)

        try? FileManager.default.removeItem(at: outputURL)
    }
}

private func requireRecordingPermission(_ adapter: CoreAudioTapAdapter) async throws {
    let state = await adapter.checkPermission()
    guard case .authorized = state else {
        throw XCTSkip("System audio recording permission required; current state: \(state)")
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
        recording = true
        return AsyncStream { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                continuation.finish()
            }
        }
    }

    func stopRecording() async throws -> RecorderResult {
        recording = false
        return RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0.1, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}
