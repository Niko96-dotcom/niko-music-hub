import AppCore
import CoreAudio
import Foundation

protocol SystemAudioRecordingSession: AnyObject, Sendable {
    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void,
        onEnded: @escaping @Sendable () -> Void
    ) async throws
    func cancelStart() async
    func stop() async throws -> RecorderResult
}

extension SystemAudioRecordingSession {
    func cancelStart() async {}
}

public final class CoreAudioTapAdapter: @unchecked Sendable, AudioCapturePort {
    private final class RecordingContext: @unchecked Sendable {
        let session: any SystemAudioRecordingSession
        let outputURL: URL
        let continuation: AsyncStream<RecorderAudioLevel>.Continuation
        private let lock = NSLock()
        private var didFinishStream = false
        private var didFinishStart = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []

        init(
            session: any SystemAudioRecordingSession,
            outputURL: URL,
            continuation: AsyncStream<RecorderAudioLevel>.Continuation
        ) {
            self.session = session
            self.outputURL = outputURL
            self.continuation = continuation
        }

        func finishStream() {
            let shouldFinish = lock.withLock { () -> Bool in
                guard !didFinishStream else { return false }
                didFinishStream = true
                return true
            }
            if shouldFinish {
                continuation.finish()
            }
        }

        func waitUntilStartFinishes() async {
            await withCheckedContinuation { continuation in
                let resumeImmediately = lock.withLock { () -> Bool in
                    guard !didFinishStart else { return true }
                    startWaiters.append(continuation)
                    return false
                }
                if resumeImmediately {
                    continuation.resume()
                }
            }
        }

        func signalStartFinished() {
            let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                guard !didFinishStart else { return [] }
                didFinishStart = true
                let pending = startWaiters
                startWaiters.removeAll()
                return pending
            }
            waiters.forEach { $0.resume() }
        }
    }

    private final class StopFlight: @unchecked Sendable {
        let task: Task<RecorderResult, any Error>

        init(task: Task<RecorderResult, any Error>) {
            self.task = task
        }
    }

    private enum State {
        case idle
        case starting(RecordingContext, autoStopRequested: Bool)
        case recording(RecordingContext)
        case stopping(RecordingContext, StopFlight)
        case completed(RecorderResult)
    }

    private enum StopAction {
        case cancelStart(RecordingContext)
        case awaitStop(Task<RecorderResult, any Error>)
        case returnCompleted(RecorderResult)
        case noRecording
    }

    private let stateLock = NSLock()
    private var state: State = .idle
    private let sessionFactory: @Sendable () -> any SystemAudioRecordingSession

    public var recording: Bool {
        stateLock.withLock {
            switch state {
            case .starting, .recording, .stopping:
                true
            case .idle, .completed:
                false
            }
        }
    }

    public init() {
        self.sessionFactory = { ResilientSystemAudioRecordingSession() }
    }

    init(sessionFactory: @escaping @Sendable () -> any SystemAudioRecordingSession) {
        self.sessionFactory = sessionFactory
    }

    private func macOSVersion() -> (major: Int, minor: Int) {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return (version.majorVersion, version.minorVersion)
    }

    public func isCompatibleMacOS() -> Bool {
        let (major, minor) = macOSVersion()
        if major > 14 { return true }
        if major == 14 { return minor >= 2 }
        return false
    }

    public func checkPermission() async -> RecorderPermissionState {
        // CoreAudio process taps use the system-audio capture privacy prompt
        // (`NSAudioCaptureUsageDescription`). Apple does not expose a public
        // preflight/request API for that permission, so the first real
        // `AudioDeviceStart` is what requests it.
        return .authorized
    }

    public func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    public func startRecording(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?
    ) async throws -> AsyncStream<RecorderAudioLevel> {
        guard isCompatibleMacOS() else {
            let (major, minor) = macOSVersion()
            throw RecorderError.incompatibleMacOS(
                minimumVersion: "14.2",
                currentVersion: "\(major).\(minor)"
            )
        }

        let permission = await checkPermission()
        switch permission {
        case .authorized:
            break
        case .denied:
            throw RecorderError.permissionDenied
        case .restricted:
            throw RecorderError.permissionRestricted
        case .notDetermined:
            throw RecorderError.permissionDenied
        }

        let tapSession = sessionFactory()
        // Levels are display-only snapshots: PCM has already been written synchronously
        // before this callback, and auto-stop is evaluated below on the producer side.
        // Retaining only the newest value prevents a stalled UI consumer from accumulating
        // an unbounded real-time callback backlog.
        let (stream, continuation) = AsyncStream.makeStream(
            of: RecorderAudioLevel.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let context = RecordingContext(
            session: tapSession,
            outputURL: outputURL,
            continuation: continuation
        )
        let accepted = stateLock.withLock { () -> Bool in
            switch state {
            case .idle, .completed:
                state = .starting(context, autoStopRequested: false)
                return true
            case .starting, .recording, .stopping:
                return false
            }
        }
        guard accepted else {
            context.finishStream()
            throw RecorderError.apiError("Recording already in progress")
        }

        do {
            try await tapSession.start(
                outputURL: outputURL,
                preset: preset,
                maxDuration: maxDuration
            ) { [weak self] level in
                continuation.yield(level)
                self?.requestAutoStopIfNeeded(level: level, maxDuration: maxDuration)
            } onEnded: {
                continuation.finish()
            }
        } catch {
            stateLock.withLock {
                if case let .starting(current, _) = state, current === context {
                    state = .idle
                }
            }
            context.finishStream()
            context.signalStartFinished()
            try? FileManager.default.removeItem(at: outputURL)
            if error is CancellationError { throw error }
            throw mapRecordingError(error)
        }

        stateLock.withLock {
            guard case let .starting(current, autoStopRequested) = state,
                  current === context else { return }
            if autoStopRequested {
                _ = beginStopLocked(context: context)
            } else {
                state = .recording(context)
            }
        }
        context.signalStartFinished()

        return stream
    }

    public func stopRecording() async throws -> RecorderResult {
        while true {
            let action = stateLock.withLock { () -> StopAction in
                switch state {
                case .idle:
                    return .noRecording
                case let .starting(context, _):
                    state = .starting(context, autoStopRequested: true)
                    return .cancelStart(context)
                case let .recording(context):
                    return .awaitStop(beginStopLocked(context: context).task)
                case let .stopping(_, flight):
                    return .awaitStop(flight.task)
                case let .completed(result):
                    return .returnCompleted(result)
                }
            }

            switch action {
            case let .cancelStart(context):
                await context.session.cancelStart()
                await context.waitUntilStartFinishes()
                throw CancellationError()
            case let .awaitStop(task):
                return try await task.value
            case let .returnCompleted(result):
                return result
            case .noRecording:
                throw RecorderError.apiError("No active recording")
            }
        }
    }

    private func requestAutoStopIfNeeded(level: RecorderAudioLevel, maxDuration: TimeInterval?) {
        guard let maxDuration, level.elapsedTime >= maxDuration else { return }
        stateLock.withLock {
            switch state {
            case let .starting(context, autoStopRequested):
                if !autoStopRequested {
                    state = .starting(context, autoStopRequested: true)
                }
            case let .recording(context):
                _ = beginStopLocked(context: context)
            case .idle, .stopping, .completed:
                break
            }
        }
    }

    /// Must be called while `stateLock` is held.
    private func beginStopLocked(context: RecordingContext) -> StopFlight {
        let task = Task<RecorderResult, any Error> { [self] in
            do {
                let result = try await context.session.stop()
                completeStop(context: context, result: result)
                return result
            } catch {
                let mapped = mapRecordingError(error)
                failStop(context: context)
                throw mapped
            }
        }
        let flight = StopFlight(task: task)
        state = .stopping(context, flight)
        return flight
    }

    private func completeStop(context: RecordingContext, result: RecorderResult) {
        stateLock.withLock {
            guard case let .stopping(current, _) = state, current === context else { return }
            state = .completed(result)
        }
        context.finishStream()
    }

    private func failStop(context: RecordingContext) {
        stateLock.withLock {
            guard case let .stopping(current, _) = state, current === context else { return }
            state = .idle
        }
        context.finishStream()
    }

    private func mapRecordingError(_ error: Error) -> RecorderError {
        if let error = error as? RecorderError {
            return error
        }
        if let error = error as? SystemAudioTapError {
            return RecorderError.apiError(error.localizedDescription)
        }
        return RecorderError.apiError(error.localizedDescription)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
