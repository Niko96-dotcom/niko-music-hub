import AppCore
import Foundation

public enum RecorderPermissionState: Sendable {
    case authorized
    case denied(needsSettings: Bool)
    case restricted
    case notDetermined
}

public enum RecorderError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case permissionRestricted
    case apiError(String)
    case writeError(String)
    case verificationFailed(String)
    case incompatibleMacOS(minimumVersion: String, currentVersion: String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Audio recording permission was denied. Please enable access in System Settings."
        case .permissionRestricted:
            return "Audio recording is restricted on this device."
        case .apiError(let message):
            return "Audio capture failed: \(message)"
        case .writeError(let message):
            return "Could not save recording: \(message)"
        case .verificationFailed(let message):
            return "Recording verification failed: \(message)"
        case .incompatibleMacOS(let minimum, let current):
            return "macOS \(current) is too old. This feature requires macOS \(minimum) or later."
        }
    }
}

public struct RecorderAudioLevel: Sendable {
    public let peak: Float
    public let average: Float
    public let elapsedTime: TimeInterval

    public init(peak: Float, average: Float, elapsedTime: TimeInterval) {
        self.peak = peak
        self.average = average
        self.elapsedTime = elapsedTime
    }
}

public struct RecorderResult: Sendable {
    public let outputURL: URL
    public let duration: TimeInterval
    public let sampleRate: Int
    public let bitDepth: Int
    public let channelCount: Int

    public init(outputURL: URL, duration: TimeInterval, sampleRate: Int, bitDepth: Int, channelCount: Int) {
        self.outputURL = outputURL
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
    }
}

public protocol AudioCapturePort: Sendable {
    var recording: Bool { get }
    func checkPermission() async -> RecorderPermissionState
    func requestPermission() async -> RecorderPermissionState
    func isCompatibleMacOS() -> Bool
    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel>
    func stopRecording() async throws -> RecorderResult
}
