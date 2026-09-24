import AVFAudio
import AudioToolbox
import CoreAudio
import XCTest
@testable import FeatureAudioRecorder

/// The private aggregate carries the output device's own input streams (an audio
/// interface's mics) ahead of the tap. On a Universal Audio Thunderbolt the IO proc sees
/// `[10-ch interface input, 2-ch tap]`; wrapping that whole list in the tap's stereo
/// format failed every callback, so Core Audio capture never produced PCM and the
/// recorder fell back to ScreenCaptureKit. Only the tap's buffers may reach the pipeline.
final class SystemAudioTapInputLayoutTests: XCTestCase {
    private let frames = 480

    // MARK: Layout resolution

    func testInterfaceInputThenTapSelectsTheTapStream() throws {
        let layout = try SystemAudioTapInputLayout.resolve(
            aggregateInputChannels: [10, 2],
            outputDeviceInputChannels: [10],
            tapFormat: tapFormat(interleaved: true)
        )
        XCTAssertEqual(layout, SystemAudioTapInputLayout(totalBufferCount: 2, tapBuffers: 1..<2))
    }

    func testTapOnlyLayoutSelectsTheOnlyBuffer() throws {
        let layout = try SystemAudioTapInputLayout.resolve(
            aggregateInputChannels: [2],
            outputDeviceInputChannels: [],
            tapFormat: tapFormat(interleaved: true)
        )
        XCTAssertEqual(layout, SystemAudioTapInputLayout(totalBufferCount: 1, tapBuffers: 0..<1))
    }

    func testDeinterleavedTapAfterInterfaceInputSelectsBothTapBuffers() throws {
        let layout = try SystemAudioTapInputLayout.resolve(
            aggregateInputChannels: [10, 1, 1],
            outputDeviceInputChannels: [10],
            tapFormat: tapFormat(interleaved: false)
        )
        XCTAssertEqual(layout, SystemAudioTapInputLayout(totalBufferCount: 3, tapBuffers: 1..<3))
    }

    func testUnrecognizedLayoutsFailWithADiagnosticInsteadOfGuessing() {
        let cases: [(aggregate: [UInt32], device: [UInt32], interleaved: Bool)] = [
            ([2, 10], [10], true),   // tap first: not the documented composition
            ([10], [10], true),      // tap stream missing
            ([10, 2, 2], [10], true), // an extra stream nobody accounts for
            ([8, 2], [10], true),    // interface prefix does not match the device
            ([10, 2], [10], false),  // tap shape does not match its format
            ([], [], true)
        ]
        for (aggregate, device, interleaved) in cases {
            XCTAssertThrowsError(try SystemAudioTapInputLayout.resolve(
                aggregateInputChannels: aggregate,
                outputDeviceInputChannels: device,
                tapFormat: tapFormat(interleaved: interleaved)
            ), "\(aggregate) / \(device)") { error in
                guard case .apiError(let message) = error as? RecorderError else {
                    return XCTFail("expected RecorderError.apiError, got \(error)")
                }
                XCTAssertTrue(message.contains("stream layout"), message)
                XCTAssertTrue(message.contains("\(aggregate)"), "the diagnostic names the aggregate layout: \(message)")
            }
        }
    }

    // MARK: Buffer selection

    func testSelectorHandsOnlyTheTapBufferWithItsFrameCount() throws {
        let format = tapFormat(interleaved: true)
        let layout = try SystemAudioTapInputLayout.resolve(
            aggregateInputChannels: [10, 2],
            outputDeviceInputChannels: [10],
            tapFormat: format
        )
        let input = SyntheticBufferList(channels: [10, 2], frames: frames, fill: [0.25, 0.001])
        let selector = SystemAudioTapInputSelector(layout: layout)

        try input.withPointer { pointer in
            let selected = try XCTUnwrap(selector.tapBuffers(of: pointer))
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: selected))
            XCTAssertEqual(buffers.count, 1)
            XCTAssertEqual(buffers[0].mNumberChannels, 2)
            XCTAssertEqual(buffers[0].mData, input.data(at: 1), "the tap's memory, not the interface input")
            XCTAssertEqual(
                RecorderPCMBufferLayout.frameCount(bufferList: selected, streamDescription: format),
                AVAudioFrameCount(frames)
            )
            XCTAssertEqual(RecorderPCMBufferLayout.usableByteCount(bufferList: selected), Int64(frames * 8))

            var description = format
            let avFormat = try XCTUnwrap(AVAudioFormat(streamDescription: &description))
            XCTAssertNotNil(
                AVAudioPCMBuffer(pcmFormat: avFormat, bufferListNoCopy: selected, deallocator: nil),
                "the selected view must wrap cleanly in the tap's format"
            )
        }
    }

    func testSelectorHandsBothDeinterleavedTapBuffers() throws {
        let format = tapFormat(interleaved: false)
        let layout = try SystemAudioTapInputLayout.resolve(
            aggregateInputChannels: [10, 1, 1],
            outputDeviceInputChannels: [10],
            tapFormat: format
        )
        let input = SyntheticBufferList(channels: [10, 1, 1], frames: frames, fill: [0.25, 0.001, 0.002])
        let selector = SystemAudioTapInputSelector(layout: layout)

        try input.withPointer { pointer in
            let selected = try XCTUnwrap(selector.tapBuffers(of: pointer))
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: selected))
            XCTAssertEqual(buffers.count, 2)
            XCTAssertEqual(buffers[0].mData, input.data(at: 1))
            XCTAssertEqual(buffers[1].mData, input.data(at: 2))
            XCTAssertEqual(
                RecorderPCMBufferLayout.frameCount(bufferList: selected, streamDescription: format),
                AVAudioFrameCount(frames)
            )
            XCTAssertEqual(RecorderPCMBufferLayout.usableByteCount(bufferList: selected), Int64(frames * 4 * 2))
        }
    }

    func testSelectorRejectsACycleWhoseBufferCountNoLongerMatches() throws {
        let layout = try SystemAudioTapInputLayout.resolve(
            aggregateInputChannels: [10, 2],
            outputDeviceInputChannels: [10],
            tapFormat: tapFormat(interleaved: true)
        )
        let input = SyntheticBufferList(channels: [2], frames: frames, fill: [0.001])
        let selector = SystemAudioTapInputSelector(layout: layout)

        input.withPointer { pointer in
            XCTAssertNil(selector.tapBuffers(of: pointer), "a reshaped cycle must not be guessed at")
        }
    }

    // MARK: Session

    func testSessionDeliversTapPCMNotStructuralNoDataWhenTheInterfaceHasInputs() throws {
        let hal = FakeTapHAL(hang: .none, outputDeviceInputChannels: [10], interfaceInputIsLive: true)
        let session = SystemAudioProcessTapSession(
            makeTapDescription: { CATapDescription(stereoMixdownOfProcesses: []) },
            hal: hal.hal
        )
        let record = DeliveryRecord()
        try session.startSynchronously(generation: 3, callbacks: record.callbacks)
        defer { session.stopSynchronously() }

        try waitUntil { record.snapshot.pcm >= 3 }
        let snapshot = record.snapshot
        XCTAssertEqual(snapshot.structural, 0, "every 2-buffer cycle must wrap, not report structural no-data")
        XCTAssertEqual(snapshot.channels, 2)
        XCTAssertEqual(snapshot.frames, AVAudioFrameCount(frames))
        XCTAssertEqual(snapshot.bytes, Int64(frames * 8), "byte accounting counts only the tap")
        XCTAssertFalse(snapshot.sawNonZero, "the live interface input must never reach the recording")
        XCTAssertEqual(snapshot.generations, [3])
    }

    func testSessionDeliversTheTapSignalAlongsideASilentInterface() throws {
        let hal = FakeTapHAL(hang: .none, echoesTone: { true }, outputDeviceInputChannels: [10])
        let session = SystemAudioProcessTapSession(
            makeTapDescription: { CATapDescription(stereoMixdownOfProcesses: []) },
            hal: hal.hal
        )
        let record = DeliveryRecord()
        try session.startSynchronously(generation: 1, callbacks: record.callbacks)
        defer { session.stopSynchronously() }

        try waitUntil { record.snapshot.pcm >= 3 }
        XCTAssertTrue(record.snapshot.sawNonZero, "the tap's audio is what gets recorded")
        XCTAssertEqual(record.snapshot.structural, 0)
    }

    func testUnrecognizedAggregateLayoutFailsTheCoreAudioAttemptCleanly() {
        let hal = FakeTapHAL(hang: .none, outputDeviceInputChannels: [10], aggregateInputChannels: [2, 10])
        let session = SystemAudioProcessTapSession(
            makeTapDescription: { CATapDescription(stereoMixdownOfProcesses: []) },
            hal: hal.hal
        )
        let record = DeliveryRecord()

        XCTAssertThrowsError(try session.startSynchronously(generation: 1, callbacks: record.callbacks)) { error in
            guard case .apiError(let message) = error as? RecorderError else {
                return XCTFail("expected a diagnostic RecorderError.apiError, got \(error)")
            }
            XCTAssertTrue(message.contains("stream layout"), message)
        }
        XCTAssertTrue(hal.startCalls.isEmpty, "the device must never start on an unknown layout")
        XCTAssertEqual(hal.destroyedAggregates, [FakeTapHAL.aggregateID])
        XCTAssertEqual(hal.destroyedTaps, [FakeTapHAL.tapID])
        XCTAssertFalse(hal.muted)
    }

    // MARK: Permission probe

    /// Interface input noise must not make the probe say "authorized" while the tap is zero.
    func testProbeIgnoresLiveInterfaceInputWhenTheTapIsSilent() async throws {
        let scenario = ProbeScenario()
        let hal = FakeTapHAL(hang: .none, outputDeviceInputChannels: [10], interfaceInputIsLive: true)
        let tap = MutedSelfProcessTap(lookupProcessObject: { 1_234 }, makeSession: hal.makeSession)
        let probe = SystemAudioCapturePermissionProbe(makeTap: { tap }, makeTone: { FakeProbeTone(scenario: scenario) })

        let outcome = try await scenario.run(probe, timeout: 5)

        XCTAssertEqual(outcome.verdict, .blocked, "stage: \(outcome.stage)")
        XCTAssertEqual(outcome.evidence.tapStructuralNoDataCallbacks, 0)
    }

    /// A silent interface input must not hide the tap's echo of the reference tone.
    func testProbeSeesTheToneThroughTheTapBehindASilentInterface() async throws {
        let scenario = ProbeScenario()
        let hal = FakeTapHAL(
            hang: .none,
            echoesTone: { scenario.toneRendering },
            outputDeviceInputChannels: [10]
        )
        let tap = MutedSelfProcessTap(lookupProcessObject: { 1_234 }, makeSession: hal.makeSession)
        let probe = SystemAudioCapturePermissionProbe(makeTap: { tap }, makeTone: { FakeProbeTone(scenario: scenario) })

        let outcome = try await scenario.run(probe, timeout: 5)

        XCTAssertEqual(outcome.verdict, .authorized, "stage: \(outcome.stage)")
    }

    // MARK: Helpers

    private func tapFormat(interleaved: Bool) -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 48_000
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        format.mChannelsPerFrame = 2
        format.mBitsPerChannel = 32
        format.mFramesPerPacket = 1
        if interleaved {
            format.mBytesPerFrame = 8
            format.mBytesPerPacket = 8
        } else {
            format.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
            format.mBytesPerFrame = 4
            format.mBytesPerPacket = 4
        }
        return format
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met in \(timeout) s") }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

/// What a session handed to its callbacks.
private final class DeliveryRecord: @unchecked Sendable {
    struct Snapshot {
        var pcm = 0
        var structural = 0
        var channels: AVAudioChannelCount = 0
        var frames: AVAudioFrameCount = 0
        var bytes: Int64 = 0
        var sawNonZero = false
        var generations: Set<Int> = []
    }

    private let lock = NSLock()
    private var value = Snapshot()
    var snapshot: Snapshot { lock.withLock { value } }

    var callbacks: RecorderBackendCallbacks {
        RecorderBackendCallbacks(
            onPCM: { [self] generation, format, buffer, bytes in
                let nonZero = RecorderPCMWriterPipeline.containsNonZeroSample(buffer)
                lock.withLock {
                    value.pcm += 1
                    value.channels = format.channelCount
                    value.frames = buffer.frameLength
                    value.bytes = bytes
                    value.sawNonZero = value.sawNonZero || nonZero
                    value.generations.insert(generation)
                }
                return true
            },
            onStructuralNoData: { [self] _ in lock.withLock { value.structural += 1 } },
            onMetadata: { _ in },
            onRouteChange: {},
            onFailure: { _ in }
        )
    }
}

/// A hand-built IO buffer list: one interleaved float buffer per entry in `channels`.
private final class SyntheticBufferList {
    private let list: UnsafeMutableAudioBufferListPointer
    private let storage: [UnsafeMutablePointer<Float>]

    init(channels: [UInt32], frames: Int, fill: [Float]) {
        list = AudioBufferList.allocate(maximumBuffers: max(1, channels.count))
        list.count = channels.count
        storage = channels.enumerated().map { index, count in
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames * Int(count))
            samples.initialize(repeating: fill[index], count: frames * Int(count))
            return samples
        }
        for (index, count) in channels.enumerated() {
            list[index] = AudioBuffer(
                mNumberChannels: count,
                mDataByteSize: UInt32(frames * Int(count) * MemoryLayout<Float>.size),
                mData: storage[index]
            )
        }
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func data(at index: Int) -> UnsafeMutableRawPointer? { UnsafeMutableRawPointer(storage[index]) }

    func withPointer<R>(_ body: (UnsafePointer<AudioBufferList>) throws -> R) rethrows -> R {
        try body(list.unsafePointer)
    }
}
