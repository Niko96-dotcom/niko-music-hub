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
    private let locator: HelperToolLocator

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        referenceDate: Date = Date(),
        locator: HelperToolLocator = .standard()
    ) {
        self.runner = runner
        self.fileExists = fileExists
        self.referenceDate = referenceDate
        self.locator = locator
    }

    public func resolvedYtDlpURL(settings: HelperToolSettings) -> URL? {
        locator.resolve(.ytDlp, settings: settings)
    }

    public func availability(settings: HelperToolSettings) async -> YtDlpAvailability {
        guard let ytDlpURL = resolvedYtDlpURL(settings: settings) else {
            return .missing
        }

        let request = ExternalProcessRequest(
            executableURL: ytDlpURL,
            arguments: ["--version"],
            timeoutSeconds: 5
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
