import FeatureAudioConverter
import XCTest
@testable import FeatureAudioRecorder

final class RecordSystemAudioUseCaseTests: XCTestCase {
    func testExecuteStartsRecording() async throws {
        let port = MockAudioCapturePort()
        let useCase = RecordSystemAudioUseCase(capturePort: port)
        let tempDir = FileManager.default.temporaryDirectory

        let config = RecordSystemAudioUseCase.Config(
            outputURL: tempDir,
            preset: .cubaseDefault,
            maxDuration: 1.0,
            filenameOverride: nil
        )

        let result = try await useCase.execute(config: config)

        XCTAssertEqual(result.sampleRate, 44100)
        XCTAssertEqual(result.bitDepth, 24)
        XCTAssertEqual(result.channelCount, 2)
    }

    func testGenerateOutputFilenameWithOverride() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let filename = useCase.generateOutputFilename(override: "Custom Name.wav")
        XCTAssertEqual(filename, "Custom Name.wav")
    }

    func testGenerateOutputFilenameWithoutOverride() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let filename = useCase.generateOutputFilename(override: nil)
        XCTAssertTrue(filename.hasPrefix("Recording "))
        XCTAssertTrue(filename.hasSuffix(".wav"))
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
        return RecorderResult(
            outputURL: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 0.1,
            sampleRate: 44100,
            bitDepth: 24,
            channelCount: 2
        )
    }
}
