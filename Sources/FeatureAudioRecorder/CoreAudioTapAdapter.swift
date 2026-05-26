import AppCore
import AVFoundation
import CoreAudio
import Foundation

public final class CoreAudioTapAdapter: @unchecked Sendable, AudioCapturePort {
    private var _isRecording = false
    private var session: SystemAudioProcessTapSession?
    private var levelContinuation: AsyncStream<RecorderAudioLevel>.Continuation?
    private var outputURL: URL?
    private var preset: AudioPreset?

    public var recording: Bool { _isRecording }

    public init() {}

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
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied(needsSettings: true)
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    public func requestPermission() async -> RecorderPermissionState {
        let granted = await AVCaptureDevice.requestAccess(for: AVMediaType.audio)
        return granted ? .authorized : .denied(needsSettings: true)
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

        let tapSession = SystemAudioProcessTapSession()
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
        } catch let error as SystemAudioTapError {
            resetRecordingState()
            continuation.finish()
            throw RecorderError.apiError(error.localizedDescription)
        } catch let error as RecorderError {
            resetRecordingState()
            continuation.finish()
            throw error
        } catch {
            resetRecordingState()
            continuation.finish()
            throw RecorderError.apiError(error.localizedDescription)
        }

        return stream
    }

    public func stopRecording() async throws -> RecorderResult {
        guard _isRecording else {
            throw RecorderError.apiError("No active recording")
        }

        guard let tapSession = session else {
            throw RecorderError.apiError("Recording session not initialized")
        }

        let result: RecorderResult
        do {
            result = try tapSession.stop()
        } catch let error as SystemAudioTapError {
            throw RecorderError.apiError(error.localizedDescription)
        }

        let continuation = levelContinuation
        resetRecordingState()
        continuation?.finish()

        return result
    }

    private func resetRecordingState() {
        _isRecording = false
        session = nil
        outputURL = nil
        preset = nil
        levelContinuation = nil
    }
}
