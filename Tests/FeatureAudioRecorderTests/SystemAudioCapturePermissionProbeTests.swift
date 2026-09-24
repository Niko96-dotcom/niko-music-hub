import XCTest
@testable import FeatureAudioRecorder

/// Drives the probe's ordering, warm-up, and deadline with a fake tap and tone that run on
/// a 10 ms clock. No Core Audio object is created.
final class SystemAudioCapturePermissionProbeTests: XCTestCase {
    func testToneNeverRendersBeforeTheMutedTapDeliversAudio() async throws {
        let scenario = ProbeScenario()
        let probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, script: .echoesTone))

        let outcome = try await scenario.run(probe)

        XCTAssertEqual(outcome.verdict, .authorized)
        XCTAssertEqual(scenario.renderTicksWithoutMutedTap, 0, "the tone must never render while no muted tap is running")
        try scenario.assertOrder("tap.firstBuffer", before: "tone.start")
        try scenario.assertOrder("tone.stop", before: "tap.stop")
    }

    func testTapStartupZerosFollowedByTheToneAreNotBlocked() async throws {
        // A tap that needs 0.5 s before real audio flows is slow, not a permission block.
        let scenario = ProbeScenario()
        var probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, script: .zerosThenEchoesTone(zeroBuffers: 50)))
        probe.timing.observationWindow = .milliseconds(1_500)

        let outcome = try await scenario.run(probe)

        XCTAssertEqual(outcome.verdict, .authorized)
    }

    func testAllZeroTapIsBlockedOnlyAtTheEndOfTheObservationWindow() async throws {
        let scenario = ProbeScenario()
        let probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, script: .allZeros))

        let outcome = try await scenario.run(probe)
        let finished = ContinuousClock.now

        XCTAssertEqual(outcome.verdict, .blocked)
        let toneStarted = try XCTUnwrap(scenario.toneStartedAt)
        XCTAssertGreaterThanOrEqual(toneStarted.duration(to: finished), probe.timing.observationWindow)
        XCTAssertGreaterThanOrEqual(
            outcome.evidence.tapSecondsObservedAfterWarmup,
            SystemAudioCapturePermissionClassifier.requiredSilentTapSeconds
        )
    }

    func testStructuralNoDataAfterWarmupIsInconclusive() async throws {
        let scenario = ProbeScenario()
        let probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, script: .zerosThenStructuralNoData(zeroBuffers: 40)))

        let outcome = try await scenario.run(probe)

        XCTAssertEqual(outcome.verdict, .inconclusive)
    }

    func testHungTapStartIsInconclusiveWithinTheDeadlineAndNeverPlaysTheTone() async throws {
        let scenario = ProbeScenario()
        var probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, start: .hang, script: .echoesTone))
        probe.timing.deadline = .milliseconds(300)
        defer { scenario.releaseHangs() }

        let started = ContinuousClock.now
        let outcome = try await scenario.run(probe, timeout: 2)

        XCTAssertEqual(outcome.verdict, .inconclusive)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        scenario.releaseHangs()
        try await waitUntil { scenario.logged("tap.stop") }
        XCTAssertFalse(scenario.logged("tone.start"), "a tap that started after the deadline must not get a tone")
    }

    func testHungTapStopDoesNotDelayTheVerdict() async throws {
        let scenario = ProbeScenario()
        let probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, hangOnStop: true, script: .echoesTone))
        defer { scenario.releaseHangs() }

        let outcome = try await scenario.run(probe, timeout: 2)

        XCTAssertEqual(outcome.verdict, .authorized)
        try scenario.assertOrder("tone.stop", before: "tap.stop")
    }

    func testHungToneStartLiftsTheMuteAtTheDeadline() async throws {
        let scenario = ProbeScenario()
        var probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, script: .echoesTone), hangToneOnStart: true)
        probe.timing.deadline = .milliseconds(300)
        defer { scenario.releaseHangs() }

        let started = ContinuousClock.now
        let outcome = try await scenario.run(probe, timeout: 2)

        XCTAssertEqual(outcome.verdict, .inconclusive)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        try await waitUntil { scenario.logged("tap.abandon") }
        scenario.releaseHangs()
        try await waitUntil { scenario.logged("tone.stop") && scenario.logged("tap.stop") }
        try scenario.assertOrder("tone.stop", before: "tap.stop")
    }

    func testTapStartFailureNeverPlaysTheTone() async throws {
        let scenario = ProbeScenario()
        let probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, start: .fail, script: .echoesTone))

        let outcome = try await scenario.run(probe)

        XCTAssertEqual(outcome.verdict, .inconclusive)
        XCTAssertFalse(scenario.logged("tone.start"))
    }

    func testTapThatNeverDeliversAudioNeverPlaysTheTone() async throws {
        let scenario = ProbeScenario()
        let probe = scenario.probe(tap: FakeProbeTap(scenario: scenario, script: .silentIOProc))

        let outcome = try await scenario.run(probe)

        XCTAssertEqual(outcome.verdict, .inconclusive)
        XCTAssertFalse(scenario.logged("tone.start"))
        XCTAssertTrue(scenario.logged("tap.stop"))
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met in \(timeout) s") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

// MARK: - Fakes shared with the session tests

/// Shared event log plus the "is anything audible" bookkeeping for one probe run.
final class ProbeScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    private var tapRunning = false
    private var toneOn = false
    private var unmutedRenderTicks = 0
    private var toneStart: ContinuousClock.Instant?
    private var hung: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private let hangSemaphore = DispatchSemaphore(value: 0)

    func probe(tap: FakeProbeTap, hangToneOnStart: Bool = false) -> SystemAudioCapturePermissionProbe {
        SystemAudioCapturePermissionProbe(
            timing: SystemAudioCapturePermissionProbe.Timing(),
            makeTap: { tap },
            makeTone: { FakeProbeTone(scenario: self, hangOnStart: hangToneOnStart) }
        )
    }

    func run(
        _ probe: SystemAudioCapturePermissionProbe,
        timeout: TimeInterval = 5
    ) async throws -> SystemAudioCapturePermissionProbe.Outcome {
        let box = OutcomeBox()
        let done = XCTestExpectation(description: "probe returned")
        Task {
            box.value = await probe.probe()
            done.fulfill()
        }
        let result = await XCTWaiter().fulfillment(of: [done], timeout: timeout)
        guard result == .completed, let outcome = box.value else {
            releaseHangs()
            XCTFail("the probe did not return within \(timeout) s")
            throw ProbeTimedOut()
        }
        return outcome
    }

    var renderTicksWithoutMutedTap: Int { lock.withLock { unmutedRenderTicks } }
    var toneRendering: Bool { lock.withLock { toneOn } }
    var toneStartedAt: ContinuousClock.Instant? { lock.withLock { toneStart } }
    func logged(_ event: String) -> Bool { lock.withLock { events.contains(event) } }

    func assertOrder(_ first: String, before second: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let snapshot = lock.withLock { events }
        let a = try XCTUnwrap(snapshot.firstIndex(of: first), "\(first) missing from \(snapshot)", file: file, line: line)
        let b = try XCTUnwrap(snapshot.firstIndex(of: second), "\(second) missing from \(snapshot)", file: file, line: line)
        XCTAssertLessThan(a, b, "\(snapshot)", file: file, line: line)
    }

    func log(_ event: String) { lock.withLock { events.append(event) } }
    func setTapRunning(_ running: Bool) { lock.withLock { tapRunning = running } }

    func setToneOn(_ on: Bool) {
        lock.withLock {
            toneOn = on
            if on { toneStart = .now }
        }
    }

    /// One render quantum; false once the tone was stopped.
    func renderTick() -> Bool {
        lock.withLock {
            guard toneOn else { return false }
            if !tapRunning { unmutedRenderTicks += 1 }
            return true
        }
    }

    func hangUntilReleased() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                hung.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func releaseHangs() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            released = true
            defer { hung = [] }
            return hung
        }
        pending.forEach { $0.resume() }
        hangSemaphore.signal()
    }

    /// Blocking wait for `releaseHangs()` usable from the synchronous tone start.
    func waitForHangReleaseSync() {
        hangSemaphore.wait()
        // Re-signal so a second waiter (or a repeated release check) still observes release.
        hangSemaphore.signal()
    }
}

struct ProbeTimedOut: Error {}

private final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SystemAudioCapturePermissionProbe.Outcome?
    var value: SystemAudioCapturePermissionProbe.Outcome? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class FakeProbeTap: SystemAudioCaptureProbeTap, @unchecked Sendable {
    enum Start { case succeed, fail, hang }

    enum Script: Sendable {
        /// Zeros until the tone renders, then the tone (capture allowed).
        case echoesTone
        case zerosThenEchoesTone(zeroBuffers: Int)
        /// Capture withheld: every buffer is exact zero.
        case allZeros
        case zerosThenStructuralNoData(zeroBuffers: Int)
        /// The IO proc never hands over PCM.
        case silentIOProc

        func event(index: Int, toneRendering: Bool) -> SystemAudioCaptureProbeTapEvent? {
            switch self {
            case .echoesTone:
                return .pcm(seconds: 0.01, nonZero: toneRendering)
            case .zerosThenEchoesTone(let zeroBuffers):
                return .pcm(seconds: 0.01, nonZero: index >= zeroBuffers && toneRendering)
            case .allZeros:
                return .pcm(seconds: 0.01, nonZero: false)
            case .zerosThenStructuralNoData(let zeroBuffers):
                return index < zeroBuffers ? .pcm(seconds: 0.01, nonZero: false) : .structuralNoData
            case .silentIOProc:
                return nil
            }
        }
    }

    private let scenario: ProbeScenario
    private let startBehavior: Start
    private let hangOnStop: Bool
    private let script: Script
    private let lock = NSLock()
    private var emitter: Task<Void, Never>?

    init(scenario: ProbeScenario, start: Start = .succeed, hangOnStop: Bool = false, script: Script) {
        self.scenario = scenario
        self.startBehavior = start
        self.hangOnStop = hangOnStop
        self.script = script
    }

    func start(onEvent: @escaping @Sendable (SystemAudioCaptureProbeTapEvent) -> Void) async throws {
        scenario.log("tap.start")
        switch startBehavior {
        case .fail: throw RecorderError.apiError("fake tap start failure")
        case .hang: await scenario.hangUntilReleased()
        case .succeed: break
        }
        scenario.setTapRunning(true)
        let scenario = scenario
        let script = script
        let task = Task.detached {
            var index = 0
            while !Task.isCancelled {
                if let event = script.event(index: index, toneRendering: scenario.toneRendering) {
                    if index == 0 { scenario.log("tap.firstBuffer") }
                    onEvent(event)
                    index += 1
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        lock.withLock { emitter = task }
    }

    func abandon() { scenario.log("tap.abandon") }

    /// Logs when teardown begins; the mute only ends once teardown returns.
    func stop() async {
        scenario.log("tap.stop")
        lock.withLock { emitter }?.cancel()
        if hangOnStop { await scenario.hangUntilReleased() }
        scenario.setTapRunning(false)
    }
}

final class FakeProbeTone: SystemAudioCaptureProbeTone, @unchecked Sendable {
    private let scenario: ProbeScenario
    private let hangOnStart: Bool
    private let lock = NSLock()
    private var renderer: Task<Void, Never>?

    init(scenario: ProbeScenario, hangOnStart: Bool = false) {
        self.scenario = scenario
        self.hangOnStart = hangOnStart
    }

    func prepare() throws { scenario.log("tone.prepare") }

    func start(onRender: @escaping @Sendable (Double) -> Void) throws {
        scenario.log("tone.start")
        if hangOnStart { scenario.waitForHangReleaseSync() }
        scenario.setToneOn(true)
        // Like a real engine, the first quantum renders immediately.
        if scenario.renderTick() { onRender(0.01) }
        let scenario = scenario
        let task = Task.detached {
            try? await Task.sleep(for: .milliseconds(10))
            while scenario.renderTick() {
                onRender(0.01)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        lock.withLock { renderer = task }
    }

    func stop() {
        scenario.setToneOn(false)
        lock.withLock { renderer }?.cancel()
        scenario.log("tone.stop")
    }
}
