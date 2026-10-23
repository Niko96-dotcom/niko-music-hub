import Foundation

/// What a helper can do now.
public enum HelperToolStatus: Equatable, Sendable {
    /// It ran its version check; `version` is the first line of its answer.
    case ready(version: String)
    /// No saved path, Tools folder or system folder holds it.
    case missing
    /// It runs, but it is too old for YouTube (yt-dlp only, `YtDlpVersionPolicy`).
    case outdated(current: String, minimumExpected: String)
    /// It is there but did not answer: a non-zero exit, a timeout or a launch error.
    case broken(message: String)
}

/// Runs a helper with its version argument and reads the answer: yt-dlp
/// `--version` (5 s, with the staleness rule), FFmpeg and ffprobe `-version`
/// (15 s), demucs-mlx `--list-models` (30 s). It runs the executable directly,
/// never through a shell. Stateless, so run-time gates may call it off the
/// main actor.
public struct HelperToolProbe: Sendable {
    /// The locator the probe resolves with; callers that run the helper
    /// resolve its path with the same one.
    public let locator: HelperToolLocator
    private let runner: any ExternalProcessRunning
    /// Fixed "today" for tests; `nil` reads the clock on every check, so a
    /// long-running app does not judge yt-dlp against its launch date.
    private let referenceDateOverride: Date?

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        referenceDate: Date? = nil,
        locator: HelperToolLocator
    ) {
        self.locator = locator
        self.runner = runner
        self.referenceDateOverride = referenceDate
    }

    public func status(of tool: HelperTool, settings: HelperToolSettings) async -> HelperToolStatus {
        guard let executableURL = locator.resolve(tool, settings: settings) else {
            return .missing
        }
        let request = ExternalProcessRequest(
            executableURL: executableURL,
            arguments: Self.versionArguments(for: tool),
            timeoutSeconds: Self.timeoutSeconds(for: tool)
        )
        do {
            let result = try await runner.run(request)
            guard result.exitCode == 0 else {
                return .broken(message: Self.diagnosticMessage(for: tool, from: result))
            }
            let version = Self.version(of: tool, from: result.standardOutput)
            if tool == .ytDlp {
                let referenceDate = referenceDateOverride ?? Date()
                if YtDlpVersionPolicy.isStale(version: version, referenceDate: referenceDate) {
                    return .outdated(
                        current: version,
                        minimumExpected: YtDlpVersionPolicy.minimumExpectedVersion(referenceDate: referenceDate)
                    )
                }
            }
            return .ready(version: version)
        } catch {
            return .broken(message: error.localizedDescription)
        }
    }

    private static func versionArguments(for tool: HelperTool) -> [String] {
        switch tool {
        case .ytDlp: ["--version"]
        case .ffmpeg, .ffprobe: ["-version"]
        case .demucsMlx: ["--list-models"]
        }
    }

    private static func timeoutSeconds(for tool: HelperTool) -> TimeInterval {
        switch tool {
        case .ytDlp: 5
        case .ffmpeg, .ffprobe: 15
        case .demucsMlx: 30
        }
    }

    /// The first output line; demucs-mlx lists models, so its first model names it.
    private static func version(of tool: HelperTool, from output: String) -> String {
        let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init)
        guard tool == .demucsMlx else { return firstLine ?? tool.executableName }
        let firstModel = firstLine?.split(separator: "\t").first.map(String.init)
        return firstModel.map { "demucs-mlx (\($0) available)" } ?? "demucs-mlx"
    }

    private static func diagnosticMessage(for tool: HelperTool, from result: ExternalProcessResult) -> String {
        let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(tool.displayName) exited with code \(result.exitCode)." : trimmed
    }
}
