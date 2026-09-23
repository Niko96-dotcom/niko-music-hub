import CoreAudio
import XCTest
@testable import FeatureAudioRecorder

/// The live probe tap against a fake HAL: a stuck Core Audio call must never leave the
/// app muted, and blocking lookups must never run on a Swift concurrency thread.
final class MutedSelfProcessTapTests: XCTestCase {
    func testStuckAggregateCreationDoesNotKeepTheAppMutedPastTheDeadline() async throws {
        let hal = FakeTapHAL(hang: .aggregateCreation)
        defer { hal.releaseHang() }
        let scenario = ProbeScenario()
        let tap = MutedSelfProcessTap(lookupProcessObject: { 1_234 }, makeSession: hal.makeSession)
        let probe = SystemAudioCapturePermissionProbe(
            timing: SystemAudioCapturePermissionProbe.Timing(deadline: .milliseconds(300)),
            makeTap: { tap },
            makeTone: { FakeProbeTone(scenario: scenario) }
        )

        let outcome = try await scenario.run(probe, timeout: 2)

        XCTAssertEqual(outcome.verdict, .inconclusive)
        XCTAssertTrue(hal.hangPending, "the start call is still stuck")
        try await waitUntil { !hal.muted }
        XCTAssertEqual(hal.destroyedTaps, [FakeTapHAL.tapID])

        // The stuck call finishes late: it must tear down, not resurrect the tap.
        hal.releaseHang()
        try await waitUntil { hal.destroyedAggregates == [FakeTapHAL.aggregateID] }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(hal.destroyedTaps, [FakeTapHAL.tapID], "destroy is idempotent")
        XCTAssertEqual(hal.createdTaps, 1)
        XCTAssertFalse(hal.muted)
        XCTAssertFalse(scenario.logged("tone.start"))
    }

    func testHungProcessLookupRunsOnTheTapQueueAndNeverCreatesALateTap() async throws {
        let hal = FakeTapHAL(hang: .none)
        let lookupGate = DispatchSemaphore(value: 0)
        let lookupThread = LookupThreadRecord()
        defer { lookupGate.signal() }
        let scenario = ProbeScenario()
        let tap = MutedSelfProcessTap(
            lookupProcessObject: {
                lookupThread.record(onTapQueue: MutedSelfProcessTap.isOnTapQueue)
                lookupGate.wait()
                return 1_234
            },
            makeSession: hal.makeSession
        )
        let probe = SystemAudioCapturePermissionProbe(
            timing: SystemAudioCapturePermissionProbe.Timing(deadline: .milliseconds(300)),
            makeTap: { tap },
            makeTone: { FakeProbeTone(scenario: scenario) }
        )

        let started = ContinuousClock.now
        let outcome = try await scenario.run(probe, timeout: 2)

        XCTAssertEqual(outcome.verdict, .inconclusive)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        XCTAssertEqual(lookupThread.onTapQueue, true, "the blocking lookup must not pin a cooperative thread")

        lookupGate.signal()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(hal.createdTaps, 0, "a lookup that returns after the deadline must not create a tap")
        XCTAssertFalse(hal.muted)
    }

    func testStuckTeardownAfterTheToneStillLiftsTheMuteWithinTheStopDeadline() async throws {
        let scenario = ProbeScenario()
        let hal = FakeTapHAL(hang: .deviceStop, echoesTone: { scenario.toneRendering })
        defer { hal.releaseHang() }
        let tap = MutedSelfProcessTap(
            stopDeadline: .milliseconds(300),
            lookupProcessObject: { 1_234 },
            makeSession: hal.makeSession
        )
        let probe = SystemAudioCapturePermissionProbe(makeTap: { tap }, makeTone: { FakeProbeTone(scenario: scenario) })

        let outcome = try await scenario.run(probe, timeout: 3)

        XCTAssertEqual(outcome.verdict, .authorized, "the fake tap echoed the tone")
        XCTAssertTrue(scenario.logged("tone.stop"))
        try await waitUntil { hal.hangPending }
        let stopBegan = ContinuousClock.now
        try await waitUntil { !hal.muted }
        XCTAssertLessThan(stopBegan.duration(to: .now), .milliseconds(800))
        XCTAssertEqual(hal.destroyedTaps, [FakeTapHAL.tapID])
        XCTAssertTrue(hal.hangPending, "the stuck AudioDeviceStop is still stuck")

        // The stuck stop finishes late: the rest is torn down, the tap is not destroyed twice.
        hal.releaseHang()
        try await waitUntil { hal.destroyedAggregates == [FakeTapHAL.aggregateID] }
        XCTAssertEqual(hal.destroyedTaps, [FakeTapHAL.tapID])
        XCTAssertEqual(hal.createdTaps, 1)
    }

    private func waitUntil(timeout: TimeInterval = 1, _ condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met in \(timeout) s") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class LookupThreadRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    var onTapQueue: Bool? { lock.withLock { value } }
    func record(onTapQueue: Bool) { lock.withLock { value = onTapQueue } }
}

/// Stands in for the HAL objects of one tap graph. Creating the process tap mutes the
/// app, exactly like `CATapMuteBehavior.muted`; destroying it un-mutes. A started device
/// delivers 10 ms float buffers that carry the tone whenever `echoesTone` says it plays.
final class FakeTapHAL: @unchecked Sendable {
    enum Hang { case none, aggregateCreation, deviceStop }

    static let tapID = AudioObjectID(0x7FFF_FF10)
    static let aggregateID = AudioObjectID(0x7FFF_FF11)
    private static let outputDeviceID = AudioObjectID(0x7FFF_FF12)
    private static let fakeIOProc: AudioDeviceIOProcID = { _, _, _, _, _, _, _ in noErr }

    private let lock = NSLock()
    private let hang: Hang
    private let echoesTone: @Sendable () -> Bool
    private let hangGate = DispatchSemaphore(value: 0)
    private var released = false
    private var tapCreates = 0
    private var tapDestroys: [AudioObjectID] = []
    private var aggregateDestroys: [AudioObjectID] = []
    private var pending = false
    private var isMuted = false
    private var ioBlock: AudioDeviceIOBlock?
    private var ioQueue: DispatchQueue?
    private var delivery: Task<Void, Never>?

    init(hang: Hang, echoesTone: @escaping @Sendable () -> Bool = { false }) {
        self.hang = hang
        self.echoesTone = echoesTone
    }

    var muted: Bool { lock.withLock { isMuted } }
    var createdTaps: Int { lock.withLock { tapCreates } }
    var destroyedTaps: [AudioObjectID] { lock.withLock { tapDestroys } }
    var destroyedAggregates: [AudioObjectID] { lock.withLock { aggregateDestroys } }
    var hangPending: Bool { lock.withLock { pending } }

    func releaseHang() {
        let signal = lock.withLock { () -> Bool in
            defer { released = true }
            return !released
        }
        if signal { hangGate.signal() }
    }

    private func hangIfConfigured(_ point: Hang) {
        guard hang == point else { return }
        lock.withLock { pending = true }
        hangGate.wait()
        lock.withLock { pending = false }
    }

    var makeSession: @Sendable (AudioObjectID) -> SystemAudioProcessTapSession {
        let hal = self.hal
        return { _ in
            SystemAudioProcessTapSession(
                makeTapDescription: { CATapDescription(stereoMixdownOfProcesses: []) },
                hal: hal
            )
        }
    }

    private func startDelivering() {
        let task = Task.detached { [self] in
            let frames = 480
            let byteCount = frames * 8
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames * 2)
            let list = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            let output = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            let time = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)
            defer {
                samples.deallocate()
                list.deallocate()
                output.deallocate()
                time.deallocate()
            }
            time.initialize(to: AudioTimeStamp())
            output.initialize(to: AudioBufferList())
            while !Task.isCancelled {
                guard let (block, queue) = lock.withLock({ ioBlock.map { ($0, ioQueue!) } }) else { return }
                let value: Float = echoesTone() ? 0.001 : 0
                samples.update(repeating: value, count: frames * 2)
                list.initialize(to: AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(byteCount), mData: samples)
                ))
                queue.sync { block(time, list, time, output, time) }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        lock.withLock { delivery = task }
    }

    var hal: SystemAudioTapHAL {
        SystemAudioTapHAL(
            createProcessTap: { [self] _ in
                lock.withLock {
                    tapCreates += 1
                    isMuted = true
                }
                return (noErr, Self.tapID)
            },
            destroyProcessTap: { [self] id in
                lock.withLock {
                    tapDestroys.append(id)
                    if id == Self.tapID { isMuted = false }
                }
            },
            readDefaultSystemOutputDevice: { (Self.outputDeviceID, "fake-output") },
            createAggregateDevice: { [self] _ in
                hangIfConfigured(.aggregateCreation)
                return (noErr, Self.aggregateID)
            },
            destroyAggregateDevice: { [self] id in
                lock.withLock { aggregateDestroys.append(id) }
            },
            readTapFormat: { _ in
                var format = AudioStreamBasicDescription()
                format.mSampleRate = 48_000
                format.mFormatID = kAudioFormatLinearPCM
                format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                format.mBytesPerPacket = 8
                format.mFramesPerPacket = 1
                format.mBytesPerFrame = 8
                format.mChannelsPerFrame = 2
                format.mBitsPerChannel = 32
                return (noErr, format)
            },
            readNominalSampleRate: { _ in (noErr, 48_000) },
            createIOProc: { [self] _, queue, block in
                lock.withLock {
                    ioBlock = block
                    ioQueue = queue
                }
                return (noErr, Self.fakeIOProc)
            },
            destroyIOProc: { [self] _, _ in
                lock.withLock { ioBlock = nil }
            },
            startDevice: { [self] _, _ in
                startDelivering()
                return noErr
            },
            stopDevice: { [self] _, _ in
                lock.withLock { delivery }?.cancel()
                hangIfConfigured(.deviceStop)
            },
            addPropertyListener: { _, _, _, _ in noErr },
            removePropertyListener: { _, _, _, _ in }
        )
    }
}
