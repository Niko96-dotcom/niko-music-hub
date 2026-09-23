@preconcurrency import AVFAudio
import CoreAudio
import Foundation

/// What the probe could prove about Core Audio system-audio capture for this process.
enum SystemAudioCapturePermissionVerdict: Equatable, Sendable {
    /// The tap delivered this process's own reference tone, so capture is allowed.
    case authorized
    /// The tap delivered only exact digital silence while this process was provably
    /// rendering a nonzero reference tone into it.
    case blocked
    /// Not enough evidence either way (engine or tap could not run, too few frames).
    case inconclusive
}

/// Evidence gathered while a known reference tone plays into a tap of this process.
struct SystemAudioCapturePermissionEvidence: Equatable, Sendable {
    var referenceSecondsRendered: Double = 0
    var tapSecondsObservedAfterWarmup: Double = 0
    var tapDeliveredNonZeroSample = false
    var tapStructuralNoDataCallbacks = 0
}

/// Apple offers no public preflight for the Core Audio process-tap permission
/// (`NSAudioCaptureUsageDescription`). A denied tap still returns `noErr` from
/// `AudioHardwareCreateProcessTap`/`AudioDeviceStart` and its IO proc keeps firing, but
/// every buffer is zero — indistinguishable from nothing playing. The only public-API
/// ground truth is a signal this process knows is nonzero: if a tap of our own output
/// returns exact zeros while we render a tone into it, macOS is withholding tap audio.
enum SystemAudioCapturePermissionClassifier {
    /// Reference audio that must already be flowing before tap frames count as evidence.
    static let warmupSeconds = 0.1
    /// Tap audio, observed after warmup, that must be all-zero before claiming a block.
    static let requiredSilentTapSeconds = 0.3

    static func verdict(for evidence: SystemAudioCapturePermissionEvidence) -> SystemAudioCapturePermissionVerdict {
        if evidence.tapDeliveredNonZeroSample { return .authorized }
        guard evidence.referenceSecondsRendered >= warmupSeconds + requiredSilentTapSeconds,
              evidence.tapSecondsObservedAfterWarmup >= requiredSilentTapSeconds
        else { return .inconclusive }
        return .blocked
    }
}

/// Live probe: plays a -60 dBFS tone through an output-only `AVAudioEngine` (never the
/// input node, so no microphone prompt) and reads it back through a muted tap of this
/// process, so the tone never reaches the speakers. Runs for at most `timeout`.
struct SystemAudioCapturePermissionProbe: Sendable {
    var timeout: Duration = .milliseconds(1_200)
    var pollInterval: Duration = .milliseconds(50)
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
        func inconclusive(_ stage: String) -> Outcome {
            Outcome(verdict: .inconclusive, evidence: recorder.snapshot(), stage: stage)
        }
        let engine = AVAudioEngine()
        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let toneFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return inconclusive("no output format") }

        let phaseStep = 2 * Double.pi * 1_000 / sampleRate
        let phase = ProbePhase()
        let source = AVAudioSourceNode(format: toneFormat) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            var current = phase.value
            for frame in 0..<Int(frameCount) {
                let sample = Self.referenceAmplitude * Float(sin(current))
                current += phaseStep
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            phase.value = current.truncatingRemainder(dividingBy: 2 * Double.pi)
            recorder.recordReference(seconds: Double(frameCount) / sampleRate)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: toneFormat)
        do {
            try engine.start()
        } catch {
            return inconclusive("engine start: \(error.localizedDescription)")
        }
        defer { engine.stop() }

        guard let processObject = Self.currentProcessObject() else { return inconclusive("no process object") }
        let tap = SystemAudioProcessTapSession(makeTapDescription: {
            let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
            description.name = "NikoMusicHub-PermissionProbe"
            description.isPrivate = true
            description.muteBehavior = CATapMuteBehavior.muted
            return description
        })
        let callbacks = RecorderBackendCallbacks(
            onPCM: { _, format, buffer, _ in
                recorder.recordTap(
                    seconds: Double(buffer.frameLength) / format.sampleRate,
                    nonZero: RecorderPCMWriterPipeline.containsNonZeroSample(buffer)
                )
                return true
            },
            onStructuralNoData: { _ in recorder.recordStructuralNoData() },
            onMetadata: { _ in },
            onRouteChange: {},
            onFailure: { _ in }
        )
        do {
            try await tap.start(generation: 1, callbacks: callbacks)
        } catch {
            return inconclusive("tap start: \(error.localizedDescription)")
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var verdict = SystemAudioCapturePermissionVerdict.inconclusive
        while clock.now < deadline {
            verdict = SystemAudioCapturePermissionClassifier.verdict(for: recorder.snapshot())
            if verdict != .inconclusive { break }
            try? await Task.sleep(for: pollInterval)
        }
        if verdict == .inconclusive {
            verdict = SystemAudioCapturePermissionClassifier.verdict(for: recorder.snapshot())
        }
        await tap.stop()
        return Outcome(verdict: verdict, evidence: recorder.snapshot(), stage: "sampled")
    }

    private static func currentProcessObject() -> AudioObjectID? {
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

/// Written from the engine's render thread and the tap's IO queue; read by the poll loop.
private final class ProbeEvidenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var evidence = SystemAudioCapturePermissionEvidence()

    func recordReference(seconds: Double) {
        lock.withLock { evidence.referenceSecondsRendered += seconds }
    }

    func recordTap(seconds: Double, nonZero: Bool) {
        lock.withLock {
            if nonZero { evidence.tapDeliveredNonZeroSample = true }
            if evidence.referenceSecondsRendered >= SystemAudioCapturePermissionClassifier.warmupSeconds {
                evidence.tapSecondsObservedAfterWarmup += seconds
            }
        }
    }

    func recordStructuralNoData() {
        lock.withLock { evidence.tapStructuralNoDataCallbacks += 1 }
    }

    func snapshot() -> SystemAudioCapturePermissionEvidence {
        lock.withLock { evidence }
    }
}

/// Oscillator phase, touched only by the engine's render thread.
private final class ProbePhase: @unchecked Sendable {
    var value = 0.0
}
