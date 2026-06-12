import AppCore
import Foundation
import XCTest
@testable import FeatureAudioRecorder

final class CoreAudioTapAdapterStateTests: XCTestCase {
    func testStartFailureRemovesPartialOutputAndResetsState() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("adapter_partial_\(UUID().uuidString).wav")
        let session = FailingStartSession()
        let adapter = CoreAudioTapAdapter(sessionFactory: { session })

        do {
            _ = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: nil)
            XCTFail("Expected start failure")
        } catch RecorderError.apiError(let message) {
            XCTAssertEqual(message, "forced start failure")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(adapter.recording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(session.didStart)
    }

    func testStopFailureResetsStateAndFinishesLevelStream() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("adapter_stop_failure_\(UUID().uuidString).wav")
        let session = StopFailingSession()
        let adapter = CoreAudioTapAdapter(sessionFactory: { session })
        let probe = StreamProbe()

        let stream = try await adapter.startRecording(outputURL: outputURL, preset: .cubaseDefault, maxDuration: nil)
        let consumeTask = Task {
            for await _ in stream {
                await probe.recordValue()
            }
            await probe.recordFinished()
        }
        defer { consumeTask.cancel() }

        try await waitUntil { await probe.valueCount > 0 }
        XCTAssertTrue(adapter.recording)

        do {
            _ = try await adapter.stopRecording()
            XCTFail("Expected stop failure")
        } catch RecorderError.apiError(let message) {
            XCTAssertEqual(message, "forced stop failure")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(adapter.recording)
        try await waitUntil { await probe.finished }
    }
}

private final class FailingStartSession: SystemAudioRecordingSession, @unchecked Sendable {
    private(set) var didStart = false

    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void
    ) throws {
        didStart = true
        try Data("partial".utf8).write(to: outputURL)
        throw RecorderError.apiError("forced start failure")
    }

    func stop() throws -> RecorderResult {
        throw RecorderError.apiError("unexpected stop")
    }
}

private final class StopFailingSession: SystemAudioRecordingSession, @unchecked Sendable {
    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void
    ) throws {
        onLevel(RecorderAudioLevel(peak: 0.5, average: 0.25, elapsedTime: 0.1))
    }

    func stop() throws -> RecorderResult {
        throw RecorderError.apiError("forced stop failure")
    }
}

private actor StreamProbe {
    private(set) var valueCount = 0
    private(set) var finished = false

    func recordValue() {
        valueCount += 1
    }

    func recordFinished() {
        finished = true
    }
}

private func waitUntil(
    timeout: TimeInterval = 1.0,
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TestTimeoutError()
}

private struct TestTimeoutError: Error {}
