import AppCore
import Foundation

public enum FFmpegAvailability: Equatable, Sendable {
    case missing
    case available(version: String)
    case unusable(message: String)
}

public struct FFmpegHealthChecker: Sendable {
    public static let homebrewPaths: [String] = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg"
    ]

    private let runner: any ExternalProcessRunning
    private let fileExists: @Sendable (String) -> Bool

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.runner = runner
        self.fileExists = fileExists
    }

    public static func detectFfmpeg() -> URL? {
        for path in homebrewPaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Saved settings path first, then the same Homebrew-style auto-detect paths as the health strip.
    public func resolvedFFmpegURL(settings: HelperToolSettings) -> URL? {
        if let configured = settings.ffmpeg, fileExists(configured.path) {
            return configured
        }
        for path in Self.homebrewPaths where fileExists(path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public func availability(settings: HelperToolSettings) async -> FFmpegAvailability {
        guard let ffmpegURL = resolvedFFmpegURL(settings: settings) else {
            return .missing
        }

        let request = ExternalProcessRequest(
            executableURL: ffmpegURL,
            arguments: ["-version"]
        )

        do {
            let result = try await runner.run(request)
            guard result.exitCode == 0 else {
                return .unusable(message: diagnosticMessage(from: result))
            }
            return .available(version: versionLine(from: result.standardOutput))
        } catch {
            return .unusable(message: error.localizedDescription)
        }
    }

    private func versionLine(from output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "ffmpeg"
    }

    private func diagnosticMessage(from result: ExternalProcessResult) -> String {
        let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "FFmpeg exited with code \(result.exitCode)." : trimmed
    }
}
