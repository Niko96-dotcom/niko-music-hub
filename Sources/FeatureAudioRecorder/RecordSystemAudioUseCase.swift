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
        guard let override else {
            return defaultOutputFilename(now: now)
        }
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "." }) else {
            return defaultOutputFilename(now: now)
        }
        // Lexical basename only: never resolve `.`/`..` against the CWD.
        // `NSString.lastPathComponent` splits on `/` without normalization,
        // so `../..` yields `..` (rejected) while `../Outside.mp3` yields
        // `Outside.mp3` (kept inside the output directory by the caller).
        let basename = (trimmed as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !basename.isEmpty, !basename.allSatisfy({ $0 == "." }), basename != "/" else {
            return defaultOutputFilename(now: now)
        }
        return ensureWAVExtension(basename)
    }

    private func defaultOutputFilename(now: () -> Date = Date.init) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Recording \(formatter.string(from: now())).wav"
    }

    private func ensureWAVExtension(_ filename: String) -> String {
        // The capture pipeline always writes WAV; the free-text name must end
        // in .wav so the extension never misdescribes the bytes.
        // Strip trailing dots first so "Take.wav." resolves to "Take.wav"
        // instead of "Take.wav.wav" ("take." -> "take.wav", not "take..wav").
        // All extension handling is lexical (no URL normalization) so dot
        // segments can never resolve against the CWD.
        var base = filename
        while base.hasSuffix(".") { base.removeLast() }
        guard !base.isEmpty else { return "\(filename).wav" }
        if base.lowercased().hasSuffix(".wav") {
            return base
        }
        let ext = Self.lexicalPathExtension(base)
        if !ext.isEmpty, Self.replaceableAudioExtensions.contains(ext.lowercased()) {
            let stem = Self.lexicalDeletingPathExtension(base)
            guard !stem.isEmpty, stem != ".", stem != ".." else {
                return "\(base).wav"
            }
            return "\(stem).wav"
        }
        return "\(base).wav"
    }

    /// Lexical extension: substring after the last `.`, ignoring a leading
    /// dot so hidden files like `.take` (and `.mp3`) have no extension and
    /// append `.wav` instead of resolving to the CWD name.
    private static func lexicalPathExtension(_ filename: String) -> String {
        guard let lastDot = filename.lastIndex(of: ".") else { return "" }
        if lastDot == filename.startIndex { return "" }
        let after = filename.index(after: lastDot)
        guard after != filename.endIndex else { return "" }
        // Basenames carry no `/`, but stay lexical if one ever appears.
        if filename[after...].contains("/") { return "" }
        return String(filename[after...])
    }

    private static func lexicalDeletingPathExtension(_ filename: String) -> String {
        let ext = lexicalPathExtension(filename)
        guard !ext.isEmpty else { return filename }
        return String(filename.dropLast(ext.count + 1))
    }

    private static let replaceableAudioExtensions: Set<String> = [
        "mp3", "m4a", "mp4", "aiff", "aif", "aifc", "flac", "ogg", "oga", "opus", "wma", "aac", "caf",
    ]

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
