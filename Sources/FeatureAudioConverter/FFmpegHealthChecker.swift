import AppCore
import Foundation

public enum FFmpegAvailability: Equatable, Sendable {
    case missing
    case available(version: String)
    case unusable(message: String)
}

public struct FFmpegHealthChecker: Sendable {
    private let runner: any ExternalProcessRunning
    private let fileExists: @Sendable (String) -> Bool
    private let locator: HelperToolLocator

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        locator: HelperToolLocator = .standard()
    ) {
        self.runner = runner
        self.fileExists = fileExists
        self.locator = locator
    }

    /// Saved settings path first, then managed and system search paths via the locator.
    public func resolvedFFmpegURL(settings: HelperToolSettings) -> URL? {
        locator.resolve(.ffmpeg, settings: settings)
    }

    public func availability(settings: HelperToolSettings) async -> FFmpegAvailability {
        guard let ffmpegURL = resolvedFFmpegURL(settings: settings) else {
            return .missing
        }

        let request = ExternalProcessRequest(
            executableURL: ffmpegURL,
            arguments: ["-version"],
            timeoutSeconds: 15
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
