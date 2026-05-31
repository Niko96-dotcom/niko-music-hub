import AppCore
import Foundation

public struct DownloadJobOptions: Sendable {
    public var sourceURL: URL
    public var outputDirectory: URL
    public var fileNameTemplate: String
    public var formatSelection: DownloadFormatSelection
    public var retries: Int

    public init(
        sourceURL: URL,
        outputDirectory: URL,
        fileNameTemplate: String = DownloadRequest.defaultOutputTemplate,
        formatSelection: DownloadFormatSelection = .default,
        retries: Int = 3
    ) {
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.fileNameTemplate = fileNameTemplate
        self.formatSelection = formatSelection
        self.retries = retries
    }
}

public enum DownloadUseCaseError: LocalizedError, Sendable, Equatable {
    case ytDlpUnavailable(String)
    case unsupportedURL(String)
    case downloadFailed(String)
    case outputNotFound

    public var errorDescription: String? {
        switch self {
        case let .ytDlpUnavailable(message):
            return "yt-dlp is required. \(message)"
        case let .unsupportedURL(message):
            return "This URL is not supported or yt-dlp could not access it. \(message)"
        case let .downloadFailed(message):
            return "Download failed: \(message)"
        case .outputNotFound:
            return "No output files found after download."
        }
    }
}

public final class DownloaderUseCase: @unchecked Sendable {
    private let downloader: any DownloadRunning
    private let healthChecker: YtDlpHealthChecker
    private let jobRunner: any JobRunning
    private let settingsStore: any SettingsStore
    private let simulateRunner: any ExternalProcessRunning

    public init(
        downloader: any DownloadRunning,
        healthChecker: YtDlpHealthChecker,
        jobRunner: any JobRunning,
        settingsStore: any SettingsStore,
        simulateRunner: any ExternalProcessRunning = FoundationExternalProcessRunner()
    ) {
        self.downloader = downloader
        self.healthChecker = healthChecker
        self.jobRunner = jobRunner
        self.settingsStore = settingsStore
        self.simulateRunner = simulateRunner
    }

    public func simulateAndEnqueue(url: URL, options: DownloadJobOptions) async throws -> Job {
        let settings = try settingsStore.loadSettings()

        let availability = await healthChecker.availability(settings: settings.helperTools)
        switch availability {
        case .missing:
            throw DownloadUseCaseError.ytDlpUnavailable("yt-dlp path is not set in Settings.")
        case let .unusable(message):
            throw DownloadUseCaseError.ytDlpUnavailable(message)
        case let .outdated(current, minimumExpected):
            throw DownloadUseCaseError.ytDlpUnavailable("yt-dlp version \(current) is outdated. Expected \(minimumExpected) or higher.")
        case .available:
            break
        }

        let ytDlpURL = settings.helperTools.ytDlp ?? YtDlpHealthChecker.detectYtDlp()
        guard let ytDlpURL = ytDlpURL else {
            throw DownloadUseCaseError.ytDlpUnavailable("yt-dlp path is not set in Settings and auto-detection failed.")
        }

        // Use --simulate to validate URL without actually downloading
        let simulateRequest = ExternalProcessRequest(
            executableURL: ytDlpURL,
            arguments: ["--simulate", "--print", "%(title)s", url.absoluteString],
            timeoutSeconds: 30
        )

        do {
            let result = try await simulateRunner.run(simulateRequest)
            if result.exitCode != 0 {
                throw DownloadUseCaseError.downloadFailed(Self.ytDlpFailureMessage(from: result))
            }
        } catch let error as DownloadUseCaseError {
            throw error
        } catch {
            throw DownloadUseCaseError.downloadFailed(error.localizedDescription)
        }

        let capturedUseCase = self
        let capturedURL = url
        let capturedOptions = options

        let job = jobRunner.enqueue(
            title: "Download: \(url.lastPathComponent)",
            sourceToolID: ToolFeatureID("downloader")
        ) { progress in
            try await capturedUseCase.downloadWithRetry(
                url: capturedURL,
                options: capturedOptions,
                progress: progress
            )
        }

        return job
    }

    private func downloadWithRetry(url: URL, options: DownloadJobOptions, progress: JobProgress) async throws {
        var lastError: Error?

        for attempt in 0..<options.retries {
            do {
                let settings = try settingsStore.loadSettings()
                let ytDlpURL = settings.helperTools.ytDlp ?? YtDlpHealthChecker.detectYtDlp()
                guard let ytDlpURL = ytDlpURL else {
                    throw DownloadUseCaseError.ytDlpUnavailable("yt-dlp path is not set and auto-detection failed.")
                }

                let request = DownloadRequest(
                    ytDlpURL: ytDlpURL,
                    sourceURL: url,
                    outputDirectory: options.outputDirectory,
                    outputTemplate: options.fileNameTemplate,
                    formatSelection: options.formatSelection
                )

                let result = try await downloader.download(request) { line in
                    progress.log(line)
                    if let progressPct = Self.parseProgress(from: line) {
                        progress.update(progress: progressPct, message: nil)
                    }
                }

                if result.exitCode != 0 {
                    throw DownloadUseCaseError.downloadFailed(result.standardError)
                }

                if result.outputURLs.isEmpty {
                    throw DownloadUseCaseError.outputNotFound
                }

                for outputURL in result.outputURLs {
                    progress.log("[download] Destination: \(outputURL.path)")
                }
                progress.update(progress: 1, message: "Downloaded")

                return
            } catch {
                lastError = error

                if !Self.isRetryable(error: error) {
                    throw error
                }

                if attempt < options.retries - 1 {
                    let backoffSeconds = pow(2.0, Double(attempt + 1))
                    progress.log("Retry \(attempt + 2)/\(options.retries) in \(Int(backoffSeconds))s...")
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                }
            }
        }

        throw lastError ?? DownloadUseCaseError.downloadFailed("Unknown error after \(options.retries) retries")
    }

    private static func parseProgress(from line: String) -> Double? {
        guard line.contains("[download]") else { return nil }
        let pattern = "(\\d+\\.?\\d*)%"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(line[range]) else {
            return nil
        }
        return min(max(value / 100.0, 0), 1)
    }

    private static func isRetryable(error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        let retryablePatterns = ["http error 5", "connection reset", "connection timed out", "temporary failure", "timeout"]
        return retryablePatterns.contains { message.contains($0) }
    }

    static func ytDlpFailureMessage(from result: ExternalProcessResult) -> String {
        let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        let stdout = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty {
            return stdout
        }
        return "yt-dlp exited with code \(result.exitCode)."
    }
}
