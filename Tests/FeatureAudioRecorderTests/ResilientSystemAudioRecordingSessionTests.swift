import AppCore
import AVFAudio
import Combine
import XCTest
@testable import FeatureAudioRecorder

final class ResilientSystemAudioRecordingSessionTests: XCTestCase {
    func testCoreAudioFirstHealthyBufferCompletesStartup() async throws {
        let core = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let fallback = FakeRecorderBackend(identity: .screenCaptureKit, behavior: .healthy(sampleRate: 48_000))
        let session = makeSession(core: [core], fallback: [fallback])
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        try await start(session, url: url)
        let result = try await session.stop()

        XCTAssertGreaterThan(result.frameCount, 0)
        XCTAssertEqual(result.diagnostics?.selectedBackend, "core-audio")
        XCTAssertEqual(core.startCount, 1)
        XCTAssertEqual(fallback.startCount, 0)
    }

    func testCoreAudioStructuralNoDataRetriesOnce() async throws {
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData)
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let session = makeSession(core: [first, second], fallback: [])
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        try await start(session, url: url)
        let result = try await session.stop()

        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(second.startCount, 1)
        XCTAssertEqual(result.diagnostics?.coreAudioRebuildCount, 1)
        XCTAssertEqual(result.diagnostics?.startupTimeoutCount, 1)
    }

    func testCoreAudioSecondFailureStartsScreenCaptureKit() async throws {
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData)
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData)
        let fallback = FakeRecorderBackend(identity: .screenCaptureKit, behavior: .healthy(sampleRate: 48_000))
        let session = makeSession(core: [first, second], fallback: [fallback])
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        try await start(session, url: url)
        let result = try await session.stop()
        _ = try WAVOutputVerifier().verify(
            url: result.outputURL,
            expectedSpec: WAVOutputSpec(sampleRate: 44_100, bitDepth: 24, channelCount: 2)
        )

        XCTAssertEqual(fallback.startCount, 1)
        XCTAssertEqual(result.diagnostics?.selectedBackend, "screen-capture-kit")
        XCTAssertEqual(result.diagnostics?.screenCaptureKitFallbackCount, 1)
    }

    func testFallbackIsNotUsedWhenCoreAudioProducesFrames() async throws {
        let core = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let fallback = FakeRecorderBackend(identity: .screenCaptureKit, behavior: .healthy(sampleRate: 48_000))
        let session = makeSession(core: [core], fallback: [fallback])
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        try await start(session, url: url)
        _ = try await session.stop()

        XCTAssertEqual(fallback.startCount, 0)
    }

    func testAllBackendsFailReturnsNoAudioCaptured() async throws {
        let session = makeSession(
            core: [
                FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData),
                FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData)
            ],
            fallback: [FakeRecorderBackend(identity: .screenCaptureKit, behavior: .structuralNoData)]
        )
        let url = temporaryWAV()

        do {
            try await start(session, url: url)
            XCTFail("Expected terminal no-audio failure")
        } catch RecorderError.noAudioCaptured(let message) {
            XCTAssertTrue(message.contains("core-audio"))
            XCTAssertTrue(message.contains("screen-capture-kit"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testStopDuringStartupCancelsRetryAndFallback() async throws {
        let started = expectation(description: "first backend started")
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .waitForExternalPCM, onStart: {
            started.fulfill()
        })
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let fallback = FakeRecorderBackend(identity: .screenCaptureKit, behavior: .healthy(sampleRate: 48_000))
        let session = makeSession(core: [first, second], fallback: [fallback], timeout: .seconds(5))
        let url = temporaryWAV()

        let startTask = Task {
            try await session.start(
                outputURL: url,
                preset: .cubaseDefault,
                maxDuration: nil,
                onLevel: { _ in },
                onEnded: {}
            )
        }
        await fulfillment(of: [started], timeout: 1)
        await session.cancelStart()
        do {
            try await startTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // expected
        }

        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(second.startCount, 0)
        XCTAssertEqual(fallback.startCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDefaultOutputChangeSchedulesOneDebouncedRebuild() async throws {
        let rebuilt = expectation(description: "rebuilt core audio started")
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100), onStart: {
            rebuilt.fulfill()
        })
        let session = makeSession(core: [first, second], fallback: [], debounce: .milliseconds(5))
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        try await start(session, url: url)

        for _ in 0..<8 { first.emitRouteChange() }
        await fulfillment(of: [rebuilt], timeout: 1)
        let result = try await session.stop()

        XCTAssertEqual(second.startCount, 1)
        XCTAssertEqual(result.diagnostics?.routeChangeCount, 1)
        XCTAssertEqual(result.diagnostics?.coreAudioRebuildCount, 1)
    }

    func testSampleRateChangeRebuildsConverterUsingNewExactSourceFormat() async throws {
        let rebuilt = expectation(description: "48 kHz backend started")
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 48_000), onStart: {
            rebuilt.fulfill()
        })
        let session = makeSession(core: [first, second], fallback: [], debounce: .milliseconds(1))
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        try await start(session, url: url)

        first.emitRouteChange()
        await fulfillment(of: [rebuilt], timeout: 1)
        let result = try await session.stop()

        XCTAssertEqual(result.diagnostics?.tapSampleRate, 48_000)
        XCTAssertEqual(result.diagnostics?.outputSampleRate, 44_100)
        XCTAssertGreaterThan(result.frameCount, 0)
    }

    func testRouteChangeKeepsWriterAndLevelStreamAlive() async throws {
        let rebuilt = expectation(description: "replacement wrote PCM")
        let levelCount = LockedCounter()
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100), onPCM: {
            rebuilt.fulfill()
        })
        let session = makeSession(core: [first, second], fallback: [], debounce: .milliseconds(1))
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        try await session.start(
            outputURL: url,
            preset: .cubaseDefault,
            maxDuration: nil,
            onLevel: { _ in levelCount.increment() },
            onEnded: {}
        )
        first.emitRouteChange()
        await fulfillment(of: [rebuilt], timeout: 1)
        let result = try await session.stop()

        XCTAssertGreaterThanOrEqual(levelCount.value, 2)
        XCTAssertGreaterThanOrEqual(result.frameCount, 512)
    }

    func testStaleGenerationCallbackCannotWriteAfterRebuild() async throws {
        let rebuilt = expectation(description: "replacement ready")
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100, frames: 256))
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100, frames: 256), onStart: {
            rebuilt.fulfill()
        })
        let session = makeSession(core: [first, second], fallback: [], debounce: .milliseconds(1))
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        try await start(session, url: url)

        first.emitRouteChange()
        await fulfillment(of: [rebuilt], timeout: 1)
        first.emitPCM(frames: 256) // obsolete generation; must be ignored
        let result = try await session.stop()

        XCTAssertEqual(result.frameCount, 512)
    }

    func testCoreAudioRecoveryFailureSwitchesToScreenCaptureKit() async throws {
        let fallbackReady = expectation(description: "fallback ready")
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let failedRecovery = FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData)
        let fallback = FakeRecorderBackend(identity: .screenCaptureKit, behavior: .healthy(sampleRate: 48_000), onPCM: {
            fallbackReady.fulfill()
        })
        let session = makeSession(
            core: [first, failedRecovery],
            fallback: [fallback],
            timeout: .milliseconds(20),
            debounce: .milliseconds(1)
        )
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        try await start(session, url: url)

        first.emitRouteChange()
        await fulfillment(of: [fallbackReady], timeout: 1)
        let result = try await session.stop()

        XCTAssertEqual(result.diagnostics?.selectedBackend, "screen-capture-kit")
        XCTAssertEqual(result.diagnostics?.screenCaptureKitFallbackCount, 1)
    }

    func testGenuineSilentFramesProduceValidWAV() async throws {
        let core = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100, frames: 512))
        let session = makeSession(core: [core], fallback: [])
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        try await start(session, url: url)
        let result = try await session.stop()
        _ = try WAVOutputVerifier().verify(
            url: result.outputURL,
            expectedSpec: WAVOutputSpec(sampleRate: 44_100, bitDepth: 24, channelCount: 2)
        )

        XCTAssertGreaterThan(result.frameCount, 0)
        XCTAssertEqual(result.diagnostics?.zeroBufferCallbackCount, 0)
    }

    func testBackendChangeDoesNotFinishLevelStream() async throws {
        let rebuilt = expectation(description: "replacement ready")
        let first = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100))
        let second = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100), onPCM: {
            rebuilt.fulfill()
        })
        let session = makeSession(core: [first, second], fallback: [], debounce: .milliseconds(1))
        let adapter = CoreAudioTapAdapter(sessionFactory: { session })
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let stream = try await adapter.startRecording(outputURL: url, preset: .cubaseDefault, maxDuration: nil)
        let probe = StreamLifetimeProbe()
        let consumer = Task {
            for await _ in stream { await probe.recordValue() }
            await probe.recordFinished()
        }

        first.emitRouteChange()
        await fulfillment(of: [rebuilt], timeout: 1)
        let finishedDuringRebuild = await probe.finished
        XCTAssertFalse(finishedDuringRebuild)
        _ = try await adapter.stopRecording()
        _ = await consumer.value

        let finishedAfterStop = await probe.finished
        let valueCount = await probe.valueCount
        XCTAssertTrue(finishedAfterStop)
        XCTAssertGreaterThanOrEqual(valueCount, 2)
    }

    func testConcurrentCallbacksCannotWriteAfterFinalization() async throws {
        let core = FakeRecorderBackend(identity: .coreAudio, behavior: .healthy(sampleRate: 44_100, frames: 256))
        let session = makeSession(core: [core], fallback: [])
        let url = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        try await start(session, url: url)
        let result = try await session.stop()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask { core.emitPCM(frames: 256) }
            }
        }
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, AVAudioFramePosition(result.frameCount))
    }

    @MainActor
    func testSuccessfulFallbackAddsOneOutputInboxItem() async throws {
        let session = makeSession(
            core: [
                FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData),
                FakeRecorderBackend(identity: .coreAudio, behavior: .structuralNoData)
            ],
            fallback: [FakeRecorderBackend(identity: .screenCaptureKit, behavior: .healthy(sampleRate: 48_000))]
        )
        let adapter = CoreAudioTapAdapter(sessionFactory: { session })
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fallback-inbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = RecordingInboxStore()
        let viewModel = AudioRecorderViewModel(
            capturePort: adapter,
            useCase: RecordSystemAudioUseCase(capturePort: adapter),
            outputURL: directory,
            outputInboxStore: inbox
        )
        let recording = expectation(description: "view model becomes recording after fallback PCM")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$recordingState.sink { state in
            if state == .recording { recording.fulfill() }
        }

        await viewModel.startRecording()
        await fulfillment(of: [recording], timeout: 1)
        await viewModel.stopRecording()
        cancellable?.cancel()

        XCTAssertEqual(try inbox.listItems().count, 1)
        XCTAssertEqual(viewModel.recordingState, RecordingDisplayState.idle)
    }

    private func makeSession(
        core: [FakeRecorderBackend],
        fallback: [FakeRecorderBackend],
        timeout: Duration = .milliseconds(20),
        debounce: Duration = .milliseconds(5)
    ) -> ResilientSystemAudioRecordingSession {
        let coreQueue = BackendFactoryQueue(backends: core)
        let fallbackQueue = BackendFactoryQueue(backends: fallback)
        return ResilientSystemAudioRecordingSession(
            configuration: RecorderRecoveryConfiguration(startupTimeout: timeout, routeDebounce: debounce),
            coreAudioFactory: { coreQueue.next(identity: .coreAudio) },
            screenCaptureKitFactory: { fallbackQueue.next(identity: .screenCaptureKit) }
        )
    }

    private func start(_ session: ResilientSystemAudioRecordingSession, url: URL) async throws {
        try await session.start(
            outputURL: url,
            preset: .cubaseDefault,
            maxDuration: nil,
            onLevel: { _ in },
            onEnded: {}
        )
    }

    private func temporaryWAV() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("resilient-recorder-\(UUID().uuidString).wav")
    }
}

private final class BackendFactoryQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var backends: [FakeRecorderBackend]

    init(backends: [FakeRecorderBackend]) { self.backends = backends }

    func next(identity: RecorderCaptureBackendIdentity) -> any RecorderCaptureBackend {
        lock.lock()
        defer { lock.unlock() }
        if !backends.isEmpty { return backends.removeFirst() }
        return FakeRecorderBackend(identity: identity, behavior: .startFailure)
    }
}

private final class FakeRecorderBackend: @unchecked Sendable, RecorderCaptureBackend {
    enum Behavior {
        case healthy(sampleRate: Double, frames: AVAudioFrameCount = 256)
        case structuralNoData
        case waitForExternalPCM
        case startFailure
    }

    let identity: RecorderCaptureBackendIdentity
    private let behavior: Behavior
    private let onStart: @Sendable () -> Void
    private let onPCM: @Sendable () -> Void
    private let lock = NSLock()
    private var callbacks: RecorderBackendCallbacks?
    private var generation = 0
    private var _startCount = 0
    private var _stopCount = 0

    init(
        identity: RecorderCaptureBackendIdentity,
        behavior: Behavior,
        onStart: @escaping @Sendable () -> Void = {},
        onPCM: @escaping @Sendable () -> Void = {}
    ) {
        self.identity = identity
        self.behavior = behavior
        self.onStart = onStart
        self.onPCM = onPCM
    }

    var startCount: Int { lock.withLock { _startCount } }
    var stopCount: Int { lock.withLock { _stopCount } }

    func start(generation: Int, callbacks: RecorderBackendCallbacks) async throws {
        lock.withLock {
            _startCount += 1
            self.generation = generation
            self.callbacks = callbacks
        }
        onStart()
        switch behavior {
        case .healthy(let rate, let frames):
            emitPCM(sampleRate: rate, frames: frames)
            onPCM()
        case .structuralNoData:
            callbacks.onStructuralNoData(generation)
        case .waitForExternalPCM:
            break
        case .startFailure:
            throw RecorderError.apiError("forced backend start failure")
        }
    }

    func stop() async {
        lock.withLock { _stopCount += 1 }
    }

    func emitRouteChange() {
        lock.withLock { callbacks }?.onRouteChange()
    }

    func emitPCM(sampleRate: Double = 44_100, frames: AVAudioFrameCount = 256) {
        let snapshot = lock.withLock { (generation, callbacks) }
        guard let callbacks = snapshot.1,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 2,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return }
        buffer.frameLength = frames // zero-valued storage is genuine silent PCM.
        let bytes = Int64(frames) * Int64(format.streamDescription.pointee.mBytesPerFrame) * 2
        callbacks.onMetadata(RecorderBackendMetadata(
            outputDeviceUID: identity.rawValue,
            sourceSampleRate: sampleRate,
            sourceChannelCount: 2
        ))
        _ = callbacks.onPCM(snapshot.0, format, buffer, bytes)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private actor StreamLifetimeProbe {
    private(set) var valueCount = 0
    private(set) var finished = false
    func recordValue() { valueCount += 1 }
    func recordFinished() { finished = true }
}

private final class RecordingInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [OutputInboxItem] = []
    func addItem(_ item: OutputInboxItem) throws { lock.withLock { items.append(item) } }
    func listItems() throws -> [OutputInboxItem] { lock.withLock { items } }
    func updateItem(_ item: OutputInboxItem) throws {
        lock.withLock {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index] = item
        }
    }
    func refreshAvailability() throws {}
}
