import AppCore
@preconcurrency import AVFAudio
import Foundation

struct RecorderBackendCallbacks: @unchecked Sendable {
    // AVAudio buffers are borrowed only during onPCM. Backends invoke it synchronously and
    // RecorderPCMWriterPipeline finishes conversion/write before the storage is released.
    let onPCM: (Int, AVAudioFormat, AVAudioPCMBuffer, Int64) -> Bool
    let onStructuralNoData: @Sendable (Int) -> Void
    let onMetadata: @Sendable (RecorderBackendMetadata) -> Void
    let onRouteChange: @Sendable () -> Void
    let onFailure: @Sendable (String) -> Void
}

protocol RecorderCaptureBackend: AnyObject, Sendable {
    var identity: RecorderCaptureBackendIdentity { get }
    func start(generation: Int, callbacks: RecorderBackendCallbacks) async throws
    func stop() async
}

struct RecorderRecoveryConfiguration: Sendable {
    var startupTimeout: Duration = .milliseconds(1_250)
    var routeDebounce: Duration = .milliseconds(250)
}

/// Actor-isolated lifecycle supervisor. PCM never crosses the actor: backend callbacks write
/// synchronously through the thread-safe pipeline and only lifecycle events hop onto the actor.
actor ResilientSystemAudioRecordingSession: SystemAudioRecordingSession {
    private enum State: Equatable {
        case idle
        case startingCoreAudio
        case runningCoreAudio
        case rebuildingCoreAudio
        case startingScreenCaptureKit
        case runningScreenCaptureKit
        case stopping
        case completed
        case failed
    }

    private let configuration: RecorderRecoveryConfiguration
    private let coreAudioFactory: @Sendable () -> any RecorderCaptureBackend
    private let screenCaptureKitFactory: @Sendable () -> any RecorderCaptureBackend
    private var state: State = .idle
    private var pipeline: RecorderPCMWriterPipeline?
    private var diagnostics: RecorderSessionDiagnostics?
    private var currentBackend: (any RecorderCaptureBackend)?
    private var generation = 0
    private var readinessGate: RecorderReadinessGate?
    private var routeRecoveryTask: Task<Void, Never>?
    private var failureReasons: [String] = []
    private var cancelled = false
    private var onEnded: (@Sendable () -> Void)?

    init(
        configuration: RecorderRecoveryConfiguration = RecorderRecoveryConfiguration(),
        coreAudioFactory: @escaping @Sendable () -> any RecorderCaptureBackend = {
            SystemAudioProcessTapSession()
        },
        screenCaptureKitFactory: @escaping @Sendable () -> any RecorderCaptureBackend = {
            ScreenCaptureKitAudioSession()
        }
    ) {
        self.configuration = configuration
        self.coreAudioFactory = coreAudioFactory
        self.screenCaptureKitFactory = screenCaptureKitFactory
    }

    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void,
        onEnded: @escaping @Sendable () -> Void
    ) async throws {
        guard state == .idle else { throw RecorderError.apiError("Recording session already active") }
        let newDiagnostics = RecorderSessionDiagnostics()
        let newPipeline = try RecorderPCMWriterPipeline(
            outputURL: outputURL,
            preset: preset,
            diagnostics: newDiagnostics,
            onLevel: onLevel
        )
        diagnostics = newDiagnostics
        pipeline = newPipeline
        self.onEnded = onEnded
        cancelled = false
        failureReasons = []

        if await startCoreAudioAttempt(pipeline: newPipeline, diagnostics: newDiagnostics) { return }
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }

        newDiagnostics.recordCoreAudioRebuild()
        if await startCoreAudioAttempt(pipeline: newPipeline, diagnostics: newDiagnostics) { return }
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }

        newDiagnostics.recordScreenCaptureKitFallback()
        if await startFallback(pipeline: newPipeline, diagnostics: newDiagnostics) { return }
        if cancelled { throw CancellationError() }

        state = .failed
        newPipeline.abort()
        throw terminalNoAudioError(diagnostics: newDiagnostics.snapshot())
    }

    func cancelStart() async {
        cancelled = true
        state = .stopping
        generation += 1
        readinessGate?.resolve(false)
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
        await currentBackend?.stop()
        currentBackend = nil
        pipeline?.abort()
    }

    func stop() async throws -> RecorderResult {
        guard let pipeline else { throw RecorderError.apiError("No active recording") }
        state = .stopping
        cancelled = true
        generation += 1
        readinessGate?.resolve(false)
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
        await currentBackend?.stop()
        currentBackend = nil
        do {
            let result = try pipeline.finalize()
            state = .completed
            readinessGate = nil
            onEnded = nil
            return result
        } catch {
            state = .failed
            readinessGate = nil
            onEnded = nil
            throw error
        }
    }

    private func startCoreAudioAttempt(
        pipeline: RecorderPCMWriterPipeline,
        diagnostics: RecorderSessionDiagnostics
    ) async -> Bool {
        state = .startingCoreAudio
        let ready = await startBackend(
            coreAudioFactory(),
            pipeline: pipeline,
            diagnostics: diagnostics
        )
        if ready {
            state = .runningCoreAudio
            diagnostics.select(.coreAudio)
        }
        return ready
    }

    private func startFallback(
        pipeline: RecorderPCMWriterPipeline,
        diagnostics: RecorderSessionDiagnostics
    ) async -> Bool {
        state = .startingScreenCaptureKit
        let ready = await startBackend(
            screenCaptureKitFactory(),
            pipeline: pipeline,
            diagnostics: diagnostics
        )
        if ready {
            state = .runningScreenCaptureKit
            diagnostics.select(.screenCaptureKit)
        }
        return ready
    }

    private func startBackend(
        _ backend: any RecorderCaptureBackend,
        pipeline: RecorderPCMWriterPipeline,
        diagnostics: RecorderSessionDiagnostics
    ) async -> Bool {
        generation += 1
        let backendGeneration = generation
        let gate = RecorderReadinessGate()
        readinessGate = gate
        currentBackend = backend
        pipeline.activate(generation: backendGeneration)
        diagnostics.recordAttempt(backend.identity)
        let callbacks = makeCallbacks(
            generation: backendGeneration,
            gate: gate,
            pipeline: pipeline,
            diagnostics: diagnostics
        )
        do {
            try await backend.start(generation: backendGeneration, callbacks: callbacks)
        } catch {
            failureReasons.append("\(backend.identity.rawValue) start: \(error.localizedDescription)")
            await backend.stop()
            return false
        }
        let ready = await gate.wait(timeout: configuration.startupTimeout)
        if ready { return true }
        if cancelled { return false } // cancelStart already performed the physical stop.
        if !cancelled {
            diagnostics.recordStartupTimeout()
            failureReasons.append("\(backend.identity.rawValue) readiness timeout")
        }
        await backend.stop()
        return false
    }

    private nonisolated func makeCallbacks(
        generation: Int,
        gate: RecorderReadinessGate,
        pipeline: RecorderPCMWriterPipeline,
        diagnostics: RecorderSessionDiagnostics
    ) -> RecorderBackendCallbacks {
        let pcm: (Int, AVAudioFormat, AVAudioPCMBuffer, Int64) -> Bool = {
            callbackGeneration, format, buffer, bytes in
            let wrote = pipeline.accept(
                generation: callbackGeneration,
                sourceFormat: format,
                buffer: buffer,
                inputByteCount: bytes
            )
            if wrote { gate.resolve(true) }
            return wrote
        }
        let structural: @Sendable (Int) -> Void = { callbackGeneration in
            guard callbackGeneration == generation else { return }
            diagnostics.recordStructuralNoData()
        }
        let metadata: @Sendable (RecorderBackendMetadata) -> Void = {
            diagnostics.recordMetadata($0)
        }
        let route: @Sendable () -> Void = { [weak self] in
            Task { await self?.scheduleRouteRecovery() }
        }
        let failure: @Sendable (String) -> Void = { [weak self] reason in
            Task { await self?.backendFailed(reason) }
        }
        return RecorderBackendCallbacks(
            onPCM: pcm,
            onStructuralNoData: structural,
            onMetadata: metadata,
            onRouteChange: route,
            onFailure: failure
        )
    }

    private func scheduleRouteRecovery() {
        guard state == .runningCoreAudio, routeRecoveryTask == nil else { return }
        diagnostics?.recordRouteChange()
        let delay = configuration.routeDebounce
        routeRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.recoverCoreAudio()
        }
    }

    private func backendFailed(_ reason: String) {
        failureReasons.append(reason)
        if state == .runningScreenCaptureKit {
            state = .failed
            if let diagnostics {
                pipeline?.endAfterCaptureLoss(error: terminalNoAudioError(diagnostics: diagnostics.snapshot()))
            } else {
                pipeline?.abort()
            }
            onEnded?()
        } else {
            scheduleRouteRecovery()
        }
    }

    private func recoverCoreAudio() async {
        routeRecoveryTask = nil
        guard state == .runningCoreAudio,
              !cancelled,
              let pipeline,
              let diagnostics
        else { return }
        state = .rebuildingCoreAudio
        diagnostics.recordCoreAudioRebuild()
        generation += 1
        pipeline.activate(generation: generation) // Reject old callbacks before teardown.
        await currentBackend?.stop()
        currentBackend = nil

        if await startCoreAudioAttempt(pipeline: pipeline, diagnostics: diagnostics) { return }
        guard !cancelled else { return }
        diagnostics.recordScreenCaptureKitFallback()
        if await startFallback(pipeline: pipeline, diagnostics: diagnostics) { return }

        state = .failed
        pipeline.endAfterCaptureLoss(error: terminalNoAudioError(diagnostics: diagnostics.snapshot()))
        onEnded?()
    }

    private func terminalNoAudioError(diagnostics: RecorderDiagnostics) -> RecorderError {
        let reasons = failureReasons.joined(separator: "; ")
        return .noAudioCaptured(
            "The recorder tried both system-audio capture methods, but macOS did not deliver audio frames. "
                + "Start audio playback and try again. If it keeps happening, allow Niko Music Hub in System Settings → Privacy & Security → Screen & System Audio Recording. Attempts: \(reasons). "
                + "Diagnostics: \(diagnostics.summary)."
        )
    }
}

final class RecorderReadinessGate: @unchecked Sendable {
    // One lock owns the one-shot continuation and timeout task. resolve is idempotent, so
    // PCM readiness, timeout, cancellation, and backend teardown can race safely.
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    func wait(timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolve(false)
            }
            lock.unlock()
        }
    }

    func resolve(_ value: Bool) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
