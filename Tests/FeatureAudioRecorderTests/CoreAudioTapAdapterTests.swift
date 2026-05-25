import FeatureAudioConverter
import XCTest
@testable import FeatureAudioRecorder

final class CoreAudioTapAdapterTests: XCTestCase {
    func testRecordingProducesWAVFile() async throws {
        let adapter = CoreAudioTapAdapter()
        try await requireRecordingPermission(adapter)
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_recording_\(UUID().uuidString).wav")

        let stream = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: 1.0)

        for await _ in stream {}
        let result = try await adapter.stopRecording()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(result.sampleRate, 44100)
        XCTAssertEqual(result.bitDepth, 24)
        XCTAssertEqual(result.channelCount, 2)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testWAVHasCorrectFormat() async throws {
        let adapter = CoreAudioTapAdapter()
        try await requireRecordingPermission(adapter)
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_format_\(UUID().uuidString).wav")

        let stream = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: 1.0)

        for await _ in stream {}
        let result = try await adapter.stopRecording()

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }
}

private func requireRecordingPermission(_ adapter: CoreAudioTapAdapter) async throws {
    let state = await adapter.checkPermission()
    guard case .authorized = state else {
        throw XCTSkip("System audio recording permission required; current state: \(state)")
    }
}
