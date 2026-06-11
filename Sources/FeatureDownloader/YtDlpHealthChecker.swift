import AppCore
import Foundation

public enum YtDlpAvailability: Equatable, Sendable {
    case missing
    case available(version: String)
    case outdated(current: String, minimumExpected: String)
    case unusable(message: String)
}

public struct YtDlpHealthChecker: Sendable {
    private let runner: any ExternalProcessRunning
    private let fileExists: @Sendable (String) -> Bool
    private let referenceDate: Date

    public static let homebrewPaths: [String] = [
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        "/opt/local/bin/yt-dlp"
    ]

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        referenceDate: Date = Date()
    ) {
        self.runner = runner
        self.fileExists = fileExists
        self.referenceDate = referenceDate
    }

    public func availability(settings: HelperToolSettings) async -> YtDlpAvailability {
        let ytDlpPath = settings.ytDlp ?? Self.detectYtDlp()

        guard let ytDlpURL = ytDlpPath else {
            return .missing
        }
        guard fileExists(ytDlpURL.path) else {
            return .missing
        }

        let request = ExternalProcessRequest(
            executableURL: ytDlpURL,
            arguments: ["--version"]
        )

        do {
            let result = try await runner.run(request)
            guard result.exitCode == 0 else {
                return .unusable(message: diagnosticMessage(from: result))
            }
            let version = versionLine(from: result.standardOutput)
            if YtDlpVersionPolicy.isStale(version: version, referenceDate: referenceDate) {
                return .outdated(
                    current: version,
                    minimumExpected: YtDlpVersionPolicy.minimumExpectedVersion(referenceDate: referenceDate)
                )
            }
            return .available(version: version)
        } catch {
            return .unusable(message: error.localizedDescription)
        }
    }

    public static func detectYtDlp() -> URL? {
        for path in homebrewPaths {
            let exists = FileManager.default.fileExists(atPath: path)
            if exists {
                let url = URL(fileURLWithPath: path)
                let process = Process()
                process.executableURL = url
                process.arguments = ["--version"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        return url
                    }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    private func versionLine(from output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "yt-dlp"
    }

    private func diagnosticMessage(from result: ExternalProcessResult) -> String {
        let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "yt-dlp exited with code \(result.exitCode)." : trimmed
    }
}