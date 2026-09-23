@preconcurrency import AVFAudio
import CoreAudio
import Foundation

/// What the probe could prove about Core Audio system-audio capture for this process.
enum SystemAudioCapturePermissionVerdict: Equatable, Sendable {
    /// The tap delivered nonzero audio of this process, so capture is allowed.
    case authorized
    /// For the whole observation window after warm-up, every tap buffer was exact zero
    /// while this process was provably rendering a nonzero reference tone into it.
    case blocked
    /// Not enough evidence either way. Callers must behave as if the probe never ran.
    case inconclusive
}

/// Evidence gathered while a known reference tone plays into a muted tap of this process.
struct SystemAudioCapturePermissionEvidence: Equatable, Sendable {
    /// Tap audio delivered before the tone started (tap startup; never counted as evidence).
    var tapSecondsBeforeTone: Double = 0
    /// Tap audio discarded as warm-up after the tone started.
    var tapSecondsDuringWarmup: Double = 0
    /// Tap audio after warm-up: the only tap audio that can support a `.blocked` verdict.
    var tapSecondsObservedAfterWarmup: Double = 0
    /// Tone the engine's render callback produced, in total and after warm-up.
    var referenceSecondsRendered: Double = 0
    var referenceSecondsRenderedAfterWarmup: Double = 0
    var tapDeliveredNonZeroSample = false
    var tapStructuralNoDataCallbacks = 0
    var tapStructuralNoDataCallbacksAfterWarmup = 0
}

/// Apple offers no public preflight for the Core Audio process-tap permission
/// (`NSAudioCaptureUsageDescription`). A denied tap still returns `noErr` from
/// `AudioHardwareCreateProcessTap`/`AudioDeviceStart` and its IO proc keeps firing, but
/// every buffer is zero — indistinguishable from nothing playing. The only public-API
/// ground truth is a signal this process knows is nonzero: if a tap of our own output
/// returns exact zeros while we render a tone into it, macOS is withholding tap audio.
enum SystemAudioCapturePermissionClassifier {
    /// Tap audio after the tone started that is discarded while the tone reaches the tap.
    static let warmupSeconds = 0.2
    /// Tap audio and rendered tone, both after warm-up, required before claiming a block.
    static let requiredSilentTapSeconds = 0.3

    /// The final verdict, taken only once the observation window has ended.
    static func verdict(for evidence: SystemAudioCapturePermissionEvidence) -> SystemAudioCapturePermissionVerdict {
        if evidence.tapDeliveredNonZeroSample { return .authorized }
        guard evidence.tapStructuralNoDataCallbacksAfterWarmup == 0,
              evidence.tapSecondsObservedAfterWarmup >= requiredSilentTapSeconds,
              evidence.referenceSecondsRenderedAfterWarmup >= requiredSilentTapSeconds
        else { return .inconclusive }
        return .blocked
    }
}

/// One tap IO callback, reduced to what the probe needs.
enum SystemAudioCaptureProbeTapEvent: Sendable {
    case pcm(seconds: Double, nonZero: Bool)
    case structuralNoData
}

/// A muted Core Audio tap of this process only. While it exists, this process's output
/// never reaches the speakers.
protocol SystemAudioCaptureProbeTap: AnyObject, Sendable {
    func start(onEvent: @escaping @Sendable (SystemAudioCaptureProbeTapEvent) -> Void) async throws
    func stop() async
    /// The probe gave up (deadline or cancellation) before the tone started. Callable from
    /// any thread; must lift the mute without waiting for a start that may be stuck.
    func abandon()
}

/// The reference tone. `prepare` builds the graph without rendering anything; `start`
/// renders and reports each rendered block's duration from the render thread.
protocol SystemAudioCaptureProbeTone: AnyObject, Sendable {
    func prepare() throws
    func start(onRender: @escaping @Sendable (Double) -> Void) throws
    func stop()
}

/// Live probe. Order is what keeps it inaudible and honest:
/// 1. build the tone graph (renders nothing),
/// 2. create and start the muted tap and wait until it delivers buffers,
/// 3. only then render a -60 dBFS tone, observe for a fixed window, and decide once at
///    its end,
/// 4. stop the tone before the tap, so the tone never outlives the mute.
/// The whole run has a hard deadline; on expiry the caller gets `.inconclusive` at once
/// and cleanup finishes in the background, so a stuck HAL call never blocks Stop.
struct SystemAudioCapturePermissionProbe: Sendable {
    struct Timing: Sendable {
        /// Hard cap on the whole probe, however Core Audio behaves.
        var deadline: Duration = .seconds(3)
        /// How long the started tap may take to deliver its first buffer.
        var tapReadyTimeout: Duration = .milliseconds(500)
        /// How long the tone plays; the verdict is taken only when it ends.
        var observationWindow: Duration = .milliseconds(900)
        var pollInterval: Duration = .milliseconds(20)
    }

    var timing = Timing()
    var makeTap: @Sendable () -> any SystemAudioCaptureProbeTap = { MutedSelfProcessTap() }
    var makeTone: @Sendable () -> any SystemAudioCaptureProbeTone = { ReferenceToneEngine() }
    static let referenceAmplitude: Float = 0.001

    /// The verdict plus what produced it, for host-only diagnostics.
    struct Outcome: Sendable {
        var verdict: SystemAudioCapturePermissionVerdict
        var evidence: SystemAudioCapturePermissionEvidence
        var stage: String
    }

    func run() async -> SystemAudioCapturePermissionVerdict {
        await probe().verdict
    }

    func probe() async -> Outcome {
        let recorder = ProbeEvidenceRecorder()
        let gate = ProbeOutcomeGate()
        let latch = ProbeToneLatch()
        let tap = makeTap()
        // Not awaited: after a deadline it only finishes cleanup, and the latch stops it
        // from ever starting the tone.
        Task.detached { [self] in
            await observe(tap: tap, latch: latch, recorder: recorder, gate: gate)
        }
        // Giving up before the tone started lifts the mute at once, even while a HAL
        // call inside the tap's start is stuck. Once the tone runs, the tap is already
        // up, so `observe` stops the tone and then the tap itself.
        let giveUp: @Sendable (String) -> Void = { stage in
            gate.resolve(Outcome(verdict: .inconclusive, evidence: recorder.snapshot(), stage: stage))
            if latch.abandonUnlessToneStarted() { tap.abandon() }
        }
        let deadline = timing.deadline
        let timer = Task.detached {
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled else { return }
            giveUp("deadline")
        }
        let outcome = await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            giveUp("cancelled")
        }
        timer.cancel()
        return outcome
    }

    private func observe(
        tap: any SystemAudioCaptureProbeTap,
        latch: ProbeToneLatch,
        recorder: ProbeEvidenceRecorder,
        gate: ProbeOutcomeGate
    ) async {
        func conclude(_ verdict: SystemAudioCapturePermissionVerdict, _ stage: String) {
            gate.resolve(Outcome(verdict: verdict, evidence: recorder.snapshot(), stage: stage))
        }
        let clock = ContinuousClock()
        let tone = makeTone()
        do {
            try tone.prepare()
        } catch {
            return conclude(.inconclusive, "tone prepare: \(error.localizedDescription)")
        }

        do {
            try await tap.start(onEvent: { recorder.record($0) })
        } catch {
            conclude(.inconclusive, "tap start: \(error.localizedDescription)")
            await tap.stop()
            return
        }

        // The muted tap must be running (delivering buffers) before anything renders.
        let tapReadyBy = clock.now.advanced(by: timing.tapReadyTimeout)
        while !recorder.tapDeliveredPCM, !gate.isResolved, clock.now < tapReadyBy {
            try? await Task.sleep(for: timing.pollInterval)
        }
        if recorder.snapshot().tapDeliveredNonZeroSample {
            conclude(.authorized, "tap audio before tone")
            await tap.stop()
            return
        }
        guard recorder.tapDeliveredPCM, !gate.isResolved, latch.beginTone() else {
            conclude(.inconclusive, "tap delivered no audio")
            await tap.stop()
            return
        }

        do {
            try tone.start(onRender: { recorder.recordReference(seconds: $0) })
        } catch {
            tone.stop()
            conclude(.inconclusive, "tone start: \(error.localizedDescription)")
            await tap.stop()
            return
        }
        let windowEnds = clock.now.advanced(by: timing.observationWindow)
        while clock.now < windowEnds, !gate.isResolved, !recorder.snapshot().tapDeliveredNonZeroSample {
            try? await Task.sleep(for: timing.pollInterval)
        }
        tone.stop() // Before the tap: the tone must never outlive the mute.
        let evidence = recorder.snapshot()
        if evidence.tapDeliveredNonZeroSample {
            conclude(.authorized, "sampled")
        } else if clock.now >= windowEnds {
            conclude(SystemAudioCapturePermissionClassifier.verdict(for: evidence), "sampled")
        } else {
            conclude(.inconclusive, "interrupted")
        }
        await tap.stop()
    }
}

/// Written from the tone's render thread and the tap's IO queue; read by `observe`.
private final class ProbeEvidenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var evidence = SystemAudioCapturePermissionEvidence()

    private var warmedUp: Bool {
        evidence.tapSecondsDuringWarmup >= SystemAudioCapturePermissionClassifier.warmupSeconds
    }

    var tapDeliveredPCM: Bool {
        lock.withLock { evidence.tapSecondsBeforeTone > 0 || evidence.tapSecondsDuringWarmup > 0 }
    }

    func recordReference(seconds: Double) {
        lock.withLock {
            evidence.referenceSecondsRendered += seconds
            if warmedUp { evidence.referenceSecondsRenderedAfterWarmup += seconds }
        }
    }

    func record(_ event: SystemAudioCaptureProbeTapEvent) {
        lock.withLock {
            switch event {
            case .structuralNoData:
                evidence.tapStructuralNoDataCallbacks += 1
                if warmedUp { evidence.tapStructuralNoDataCallbacksAfterWarmup += 1 }
            case .pcm(let seconds, let nonZero):
                if nonZero { evidence.tapDeliveredNonZeroSample = true }
                if evidence.referenceSecondsRendered == 0 {
                    evidence.tapSecondsBeforeTone += seconds
                } else if !warmedUp {
                    evidence.tapSecondsDuringWarmup += seconds
                } else {
                    evidence.tapSecondsObservedAfterWarmup += seconds
                }
            }
        }
    }

    func snapshot() -> SystemAudioCapturePermissionEvidence {
        lock.withLock { evidence }
    }
}

/// Decides, atomically, between "the tone starts" and "the probe gave up first".
private final class ProbeToneLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var toneStarted = false
    private var abandoned = false

    func beginTone() -> Bool {
        lock.withLock {
            guard !abandoned else { return false }
            toneStarted = true
            return true
        }
    }

    func abandonUnlessToneStarted() -> Bool {
        lock.withLock {
            guard !toneStarted else { return false }
            abandoned = true
            return true
        }
    }
}

/// One-shot result: the first of verdict, deadline, or cancellation wins.
private final class ProbeOutcomeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: SystemAudioCapturePermissionProbe.Outcome?
    private var continuation: CheckedContinuation<SystemAudioCapturePermissionProbe.Outcome, Never>?

    var isResolved: Bool { lock.withLock { outcome != nil } }

    func wait() async -> SystemAudioCapturePermissionProbe.Outcome {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> SystemAudioCapturePermissionProbe.Outcome? in
                if let outcome { return outcome }
                self.continuation = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    func resolve(_ value: SystemAudioCapturePermissionProbe.Outcome) {
        let pending = lock.withLock { () -> CheckedContinuation<SystemAudioCapturePermissionProbe.Outcome, Never>? in
            guard outcome == nil else { return nil }
            outcome = value
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}

/// Live muted tap of this process. Every blocking HAL call, including the PID lookup,
/// runs on a private serial queue, so a stuck call occupies that queue, never a Swift
/// concurrency thread, and a late start is always followed by its stop. `abandon` lifts
/// the mute from another queue without waiting for that stuck call.
final class MutedSelfProcessTap: SystemAudioCaptureProbeTap, @unchecked Sendable {
    private static let queueKey = DispatchSpecificKey<Bool>()
    private let queue = DispatchQueue(label: "NikoMusicHub.SystemAudioCapturePermissionProbe.tap")
    private let lock = NSLock()
    private var session: SystemAudioProcessTapSession?
    private var abandoned = false
    private let lookupProcessObject: @Sendable () -> AudioObjectID?
    private let makeSession: @Sendable (AudioObjectID) -> SystemAudioProcessTapSession

    init(
        lookupProcessObject: @escaping @Sendable () -> AudioObjectID? = { MutedSelfProcessTap.currentProcessObject() },
        makeSession: @escaping @Sendable (AudioObjectID) -> SystemAudioProcessTapSession = { processObject in
            SystemAudioProcessTapSession(makeTapDescription: {
                let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
                description.name = "NikoMusicHub-PermissionProbe"
                description.isPrivate = true
                description.muteBehavior = CATapMuteBehavior.muted
                return description
            })
        }
    ) {
        self.lookupProcessObject = lookupProcessObject
        self.makeSession = makeSession
        queue.setSpecific(key: Self.queueKey, value: true)
    }

    /// True on this type's private HAL queue, where every blocking Core Audio call belongs.
    static var isOnTapQueue: Bool { DispatchQueue.getSpecific(key: queueKey) == true }

    func abandon() {
        let session = lock.withLock { () -> SystemAudioProcessTapSession? in
            abandoned = true
            return self.session
        }
        guard let session else { return } // A start that has not built its session never will.
        DispatchQueue.global(qos: .userInitiated).async { session.releaseMute() }
    }

    func start(onEvent: @escaping @Sendable (SystemAudioCaptureProbeTapEvent) -> Void) async throws {
        let callbacks = RecorderBackendCallbacks(
            onPCM: { _, format, buffer, _ in
                onEvent(.pcm(
                    seconds: Double(buffer.frameLength) / format.sampleRate,
                    nonZero: RecorderPCMWriterPipeline.containsNonZeroSample(buffer)
                ))
                return true
            },
            onStructuralNoData: { _ in onEvent(.structuralNoData) },
            onMetadata: { _ in },
            onRouteChange: {},
            onFailure: { _ in }
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    try startOnQueue(callbacks: callbacks)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startOnQueue(callbacks: RecorderBackendCallbacks) throws {
        let abandonedError = RecorderError.apiError("Permission probe gave up before the tap started")
        guard !lock.withLock({ abandoned }) else { throw abandonedError }
        guard let processObject = lookupProcessObject() else {
            throw RecorderError.apiError("This process has no Core Audio process object")
        }
        let session = makeSession(processObject)
        let admitted = lock.withLock { () -> Bool in
            guard !abandoned else { return false }
            self.session = session
            return true
        }
        guard admitted else { throw abandonedError }
        try session.startSynchronously(generation: 1, callbacks: callbacks)
    }

    func stop() async {
        guard let session = lock.withLock({ session }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                session.stopSynchronously()
                continuation.resume()
            }
        }
    }

    static func currentProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &processObject
        )
        guard status == noErr, processObject != kAudioObjectUnknown else { return nil }
        return processObject
    }
}

/// Output-only `AVAudioEngine` rendering a 1 kHz sine at `referenceAmplitude`. It never
/// touches the input node, so it cannot trigger a microphone prompt.
final class ReferenceToneEngine: SystemAudioCaptureProbeTone, @unchecked Sendable {
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var prepared = false
    private var renderer: ToneRenderReporter?

    func prepare() throws {
        try lock.withLock {
            guard !prepared else { return }
            let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
            guard sampleRate > 0,
                  let toneFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            else { throw RecorderError.apiError("No output format for the reference tone") }
            let phaseStep = 2 * Double.pi * 1_000 / sampleRate
            let phase = ProbePhase()
            let renderer = ToneRenderReporter()
            let source = AVAudioSourceNode(format: toneFormat) { _, _, frameCount, audioBufferList in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                var current = phase.value
                for frame in 0..<Int(frameCount) {
                    let sample = SystemAudioCapturePermissionProbe.referenceAmplitude * Float(sin(current))
                    current += phaseStep
                    for buffer in buffers {
                        buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                    }
                }
                phase.value = current.truncatingRemainder(dividingBy: 2 * Double.pi)
                renderer.report(seconds: Double(frameCount) / sampleRate)
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: toneFormat)
            self.renderer = renderer
            prepared = true
        }
    }

    func start(onRender: @escaping @Sendable (Double) -> Void) throws {
        try lock.withLock {
            guard prepared, let renderer else { throw RecorderError.apiError("Reference tone not prepared") }
            renderer.onRender = onRender
            try engine.start()
        }
    }

    func stop() {
        lock.withLock {
            engine.stop()
            renderer?.onRender = nil
        }
    }
}

/// Hands rendered durations from the render thread to whoever started the tone.
private final class ToneRenderReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (Double) -> Void)?

    var onRender: (@Sendable (Double) -> Void)? {
        get { lock.withLock { callback } }
        set { lock.withLock { callback = newValue } }
    }

    func report(seconds: Double) {
        onRender?(seconds)
    }
}

/// Oscillator phase, touched only by the engine's render thread.
private final class ProbePhase: @unchecked Sendable {
    var value = 0.0
}
