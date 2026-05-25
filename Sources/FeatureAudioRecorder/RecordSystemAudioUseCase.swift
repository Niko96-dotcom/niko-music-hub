import AppCore
import Foundation

public final class RecordSystemAudioUseCase: Sendable {
    public enum RecordingState: Sendable {
        case idle
        case recording(startedAt: Date, fileURL: URL)
        case stopped
    }

    public struct Config: Sendable {
        public let outputURL: URL
        public let preset: AudioPreset
        public let maxDuration: TimeInterval?
        public let filenameOverride: String?

        public init(
            outputURL: URL,
            preset: AudioPreset,
            maxDuration: TimeInterval? = 1800,
            filenameOverride: String? = nil
        ) {
            self.outputURL = outputURL
            self.preset = preset
            self.maxDuration = maxDuration
            self.filenameOverride = filenameOverride
        }
    }

    private let capturePort: AudioCapturePort

    public init(capturePort: AudioCapturePort) {
        self.capturePort = capturePort
    }

    public func resolvedOutputURL(config: Config) -> URL {
        let filename = generateOutputFilename(override: config.filenameOverride)
        var finalURL = config.outputURL
        if !filename.isEmpty {
            finalURL = config.outputURL.appendingPathComponent(filename)
        }
        return resolveFilenameCollision(url: finalURL)
    }

    public func execute(config: Config) async throws -> RecorderResult {
        let finalURL = resolvedOutputURL(config: config)

        let stream = try await capturePort.startRecording(
            outputURL: finalURL,
            preset: config.preset,
            maxDuration: config.maxDuration
        )

        for await _ in stream {
        }

        return try await capturePort.stopRecording()
    }

    public func generateOutputFilename(override: String?) -> String {
        if let override = override, !override.isEmpty {
            return override
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Recording \(formatter.string(from: Date())).wav"
    }

    private func resolveFilenameCollision(url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url
        }

        let parent = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newURL = url
        while FileManager.default.fileExists(atPath: newURL.path) {
            newURL = parent.appendingPathComponent("\(filename) (\(counter)).\(ext)")
            counter += 1
        }

        return newURL
    }
}
