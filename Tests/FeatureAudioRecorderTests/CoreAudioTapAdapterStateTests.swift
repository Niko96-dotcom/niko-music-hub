import AppCore
import Foundation
import XCTest
@testable import FeatureAudioRecorder

final class CoreAudioTapAdapterStateTests: XCTestCase {
    func testThresholdBurstTriggersExactlyOneStopAndOneStreamFinish() async throws {
        let session = CountingStopSession()
        let adapter = CoreAudioTapAdapter(sessionFactory: { session })
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter_threshold_\(UUID().uuidString).wav")
        let stream = try await adapter.startRecording(
            outputURL: outputURL,
            preset: .cubaseDefault,
            maxDuration: 1
        )
        let probe = StreamProbe()
        let consumeTask = Task {
            for await _ in stream {
                await probe.recordValue()
            }
            await probe.recordFinished()
        }

        session.emitThresholdBurst(count: 100)
        try await waitUntil { await probe.finished }
        let result = try await adapter.stopRecording()
        _ = await consumeTask.value
        let finishCount = await probe.finishCount

        XCTAssertEqual(session.stopCallCount, 1)
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(result.outputURL, outputURL)
        XCTAssertFalse(adapter.recording)
    }

    func testLevelStreamCoalescesToLatestValueWhenConsumerFallsBehind() async throws {
        let session = CountingStopSession()
        let adapter = CoreAudioTapAdapter(sessionFactory: { session })
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter_levels_\(UUID().uuidString).wav")
        let stream = try await adapter.startRecording(
            outputURL: outputURL,
            preset: .cubaseDefault,
            maxDuration: nil
        )

        // Do not start consuming until after a burst, as a busy main actor would behave.
        session.emitLevelBurst(count: 100)
        _ = try await adapter.stopRecording()

        var receivedElapsedTimes: [TimeInterval] = []
        for await level in stream {
            receivedElapsedTimes.append(level.elapsedTime)
        }

        XCTAssertEqual(receivedElapsedTimes, [100])
    }

    func testManualAndAutomaticStopsShareOneInFlightResult() async throws {
        let session = CountingStopSession(stopDelayMicroseconds: 25_000)
        let adapter = CoreAudioTapAdapter(sessionFactory: { session })
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter_stop_race_\(UUID().uuidString).wav")
        _ = try await adapter.startRecording(
            outputURL: outputURL,
            preset: .cubaseDefault,
            maxDuration: 1
        )

        let resultsTask = Task {
            try await withThrowingTaskGroup(of: RecorderResult.self) { group in
                for _ in 0..<20 {
                    group.addTask {
                        try await adapter.stopRecording()
                    }
                }
                var results: [RecorderResult] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
        }
        session.emitThresholdBurst(count: 100)
        let results = try await resultsTask.value

        XCTAssertEqual(results.count, 20)
        XCTAssertTrue(results.allSatisfy { $0.outputURL == outputURL })
        XCTAssertEqual(session.stopCallCount, 1)
    }

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
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void,
        onEnded: @escaping @Sendable () -> Void
    ) async throws {
        didStart = true
        try Data("partial".utf8).write(to: outputURL)
        throw RecorderError.apiError("forced start failure")
    }

    func stop() async throws -> RecorderResult {
        throw RecorderError.apiError("unexpected stop")
    }
}

private final class StopFailingSession: SystemAudioRecordingSession, @unchecked Sendable {
    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void,
        onEnded: @escaping @Sendable () -> Void
    ) async throws {
        onLevel(RecorderAudioLevel(peak: 0.5, average: 0.25, elapsedTime: 0.1))
    }

    func stop() async throws -> RecorderResult {
        throw RecorderError.apiError("forced stop failure")
    }
}

private actor StreamProbe {
    private(set) var valueCount = 0
    private(set) var finishCount = 0
    var finished: Bool { finishCount > 0 }

    func recordValue() {
        valueCount += 1
    }

    func recordFinished() {
        finishCount += 1
    }
}

private final class CountingStopSession: SystemAudioRecordingSession, @unchecked Sendable {
    private let lock = NSLock()
    private let stopDelayMicroseconds: useconds_t
    private var levelHandler: (@Sendable (RecorderAudioLevel) -> Void)?
    private var outputURL: URL?
    private var _stopCallCount = 0

    init(stopDelayMicroseconds: useconds_t = 0) {
        self.stopDelayMicroseconds = stopDelayMicroseconds
    }

    var stopCallCount: Int {
        lock.withLock { _stopCallCount }
    }

    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void,
        onEnded: @escaping @Sendable () -> Void
    ) async throws {
        lock.withLock {
            self.outputURL = outputURL
            levelHandler = onLevel
        }
    }

    func emitThresholdBurst(count: Int) {
        let handler = lock.withLock { levelHandler }
        for _ in 0..<count {
            handler?(RecorderAudioLevel(peak: 0.8, average: 0.4, elapsedTime: 1))
        }
    }

    func emitLevelBurst(count: Int) {
        let handler = lock.withLock { levelHandler }
        for elapsedTime in 1...count {
            handler?(
                RecorderAudioLevel(
                    peak: 0.8,
                    average: 0.4,
                    elapsedTime: TimeInterval(elapsedTime)
                )
            )
        }
    }

    func stop() async throws -> RecorderResult {
        let url = lock.withLock { () -> URL? in
            _stopCallCount += 1
            return outputURL
        }
        if stopDelayMicroseconds > 0 {
            usleep(stopDelayMicroseconds)
        }
        guard let url else {
            throw RecorderError.apiError("Missing output URL")
        }
        return RecorderResult(
            outputURL: url,
            duration: 1,
            sampleRate: 44_100,
            bitDepth: 24,
            channelCount: 2,
            frameCount: 44_100
        )
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
