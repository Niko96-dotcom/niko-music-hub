import AppCore
import CoreAudio
import Foundation

protocol SystemAudioRecordingSession: AnyObject, Sendable {
    func start(
        outputURL: URL,
        preset: AudioPreset,
        maxDuration: TimeInterval?,
        onLevel: @escaping @Sendable (RecorderAudioLevel) -> Void
    ) throws
    func stop() throws -> RecorderResult
}

public final class CoreAudioTapAdapter: @unchecked Sendable, AudioCapturePort {
    private var _isRecording = false
    private var session: (any SystemAudioRecordingSession)?
    private var levelContinuation: AsyncStream<RecorderAudioLevel>.Continuation?
    private var outputURL: URL?
    private var preset: AudioPreset?
    private let sessionFactory: @Sendable () -> any SystemAudioRecordingSession

    public var recording: Bool { _isRecording }

    public init() {
        self.sessionFactory = { SystemAudioProcessTapSession() }
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

        if _isRecording {
            throw RecorderError.apiError("Recording already in progress")
        }
        _isRecording = true
        self.outputURL = outputURL
        self.preset = preset

        let tapSession = sessionFactory()
        session = tapSession

        let (stream, continuation) = AsyncStream.makeStream(of: RecorderAudioLevel.self)
        levelContinuation = continuation

        do {
            try tapSession.start(
                outputURL: outputURL,
                preset: preset,
                maxDuration: maxDuration
            ) { [weak self] level in
                continuation.yield(level)
                if let maxDuration, level.elapsedTime >= maxDuration {
                    Task { try? await self?.stopRecording() }
                }
            }
        } catch {
            cleanupAfterFailedStart(outputURL: outputURL, continuation: continuation)
            throw mapRecordingError(error)
        }

        return stream
    }

    public func stopRecording() async throws -> RecorderResult {
        guard _isRecording else {
            throw RecorderError.apiError("No active recording")
        }

        guard let tapSession = session else {
            let continuation = levelContinuation
            resetRecordingState()
            continuation?.finish()
            throw RecorderError.apiError("Recording session not initialized")
        }

        let continuation = levelContinuation
        defer {
            resetRecordingState()
            continuation?.finish()
        }

        do {
            return try tapSession.stop()
        } catch {
            throw mapRecordingError(error)
        }
    }

    private func resetRecordingState() {
        _isRecording = false
        session = nil
        outputURL = nil
        preset = nil
        levelContinuation = nil
    }

    private func cleanupAfterFailedStart(
        outputURL: URL,
        continuation: AsyncStream<RecorderAudioLevel>.Continuation
    ) {
        resetRecordingState()
        continuation.finish()
        try? FileManager.default.removeItem(at: outputURL)
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
