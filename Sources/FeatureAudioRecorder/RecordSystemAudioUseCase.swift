import AppCore
import Foundation
import NikoMusicCore

public final class RecordSystemAudioUseCase: Sendable {
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
    private let archiveRootsProvider: @Sendable () -> [URL]

    public init(
        capturePort: AudioCapturePort,
        archiveRootsProvider: @escaping @Sendable () -> [URL] = { [] }
    ) {
        self.capturePort = capturePort
        self.archiveRootsProvider = archiveRootsProvider
    }

    public func resolvedOutputURL(config: Config) -> URL {
        let filename = generateOutputFilename(override: config.filenameOverride)
        var finalURL = config.outputURL
        if !filename.isEmpty {
            finalURL = config.outputURL.appendingPathComponent(filename)
        }
        return resolveFilenameCollision(url: finalURL)
    }

    public func prepareOutputURL(config: Config) throws -> URL {
        try validateOutputLocation(config.outputURL)
        let finalURL = resolvedOutputURL(config: config)
        try ensureOutputDirectoryExists(for: finalURL)
        return finalURL
    }

    private func validateOutputLocation(_ outputFolder: URL) throws {
        try OutputWriteGuard().validateCanWriteOutput(
            to: outputFolder,
            archiveRoots: archiveRootsProvider()
        )
    }

    public func ensureOutputDirectoryExists(for fileURL: URL) throws {
        let outputDirectory = fileURL.deletingLastPathComponent()
        try validateOutputLocation(outputDirectory)
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw RecorderError.writeError(
                "Could not create output folder \(outputDirectory.path): \(error.localizedDescription)"
            )
        }
    }

    public func execute(config: Config) async throws -> RecorderResult {
        let finalURL = try prepareOutputURL(config: config)

        let stream = try await capturePort.startRecording(
            outputURL: finalURL,
            preset: config.preset,
            maxDuration: config.maxDuration
        )

        for await _ in stream {
        }

        return try await capturePort.stopRecording()
    }

    public func generateOutputFilename(override: String?, now: () -> Date = Date.init) -> String {
        if let override = override, !override.isEmpty {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            let basename = URL(fileURLWithPath: trimmed).lastPathComponent
            return basename.isEmpty ? defaultOutputFilename(now: now) : ensureWAVExtension(basename)
        }
        return defaultOutputFilename(now: now)
    }

    private func defaultOutputFilename(now: () -> Date = Date.init) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Recording \(formatter.string(from: now())).wav"
    }

    private func ensureWAVExtension(_ filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        guard url.pathExtension.isEmpty else { return filename }
        return "\(filename).wav"
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
