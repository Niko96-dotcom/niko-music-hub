import AppCore
import Foundation

public struct DownloadJobOptions: Sendable {
    public var sourceURL: URL
    public var outputDirectory: URL
    public var fileNameTemplate: String
    public var formatSelection: DownloadFormatSelection
    public var retries: Int
    public var playlistMode: DownloadPlaylistMode

    public init(
        sourceURL: URL,
        outputDirectory: URL,
        fileNameTemplate: String = DownloadRequest.defaultOutputTemplate,
        formatSelection: DownloadFormatSelection = .default,
        retries: Int = 3,
        playlistMode: DownloadPlaylistMode = .single
    ) {
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.fileNameTemplate = fileNameTemplate
        self.formatSelection = formatSelection
        self.retries = retries
        self.playlistMode = playlistMode
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

public protocol DownloaderUseCaseRunning: Sendable {
    func simulateAndEnqueue(url: URL, options: DownloadJobOptions) async throws -> Job
}

public final class DownloaderUseCase: DownloaderUseCaseRunning, @unchecked Sendable {
    private let downloader: any DownloadRunning
    private let healthChecker: YtDlpHealthChecker
    private let jobRunner: any JobRunning
    private let settingsStore: any SettingsStore
    private let simulateRunner: any ExternalProcessRunning
    private let locator: HelperToolLocator

    public init(
        downloader: any DownloadRunning,
        healthChecker: YtDlpHealthChecker,
        jobRunner: any JobRunning,
        settingsStore: any SettingsStore,
        simulateRunner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        locator: HelperToolLocator = .standard()
    ) {
        self.downloader = downloader
        self.healthChecker = healthChecker
        self.jobRunner = jobRunner
        self.settingsStore = settingsStore
        self.simulateRunner = simulateRunner
        self.locator = locator
    }

    public func simulateAndEnqueue(url: URL, options: DownloadJobOptions) async throws -> Job {
        let settings = try settingsStore.loadSettings()

        let availability = await healthChecker.availability(settings: settings.helperTools)
        switch availability {
        case .missing:
            throw DownloadUseCaseError.ytDlpUnavailable(DownloaderCopy.ytDlpMissing)
        case let .unusable(message):
            throw DownloadUseCaseError.ytDlpUnavailable(message)
        case let .outdated(current, minimumExpected):
            throw DownloadUseCaseError.ytDlpUnavailable(
                DownloaderCopy.outdatedYtDlp(current: current, minimumExpected: minimumExpected)
            )
        case .available:
            break
        }

        guard let ytDlpURL = healthChecker.resolvedYtDlpURL(settings: settings.helperTools) else {
            throw DownloadUseCaseError.ytDlpUnavailable(DownloaderCopy.ytDlpMissing)
        }

        let simulateRequest = ExternalProcessRequest(
            executableURL: ytDlpURL,
            arguments: YtDlpDownloadCommandBuilder.simulateArguments(
                formatSelection: options.formatSelection,
                sourceURL: url,
                ffmpegLocationURL: DownloaderHelperToolResolver.ffmpegLocationURL(settings: settings.helperTools, locator: locator),
                playlistMode: options.playlistMode
            ),
            environment: DownloaderHelperToolResolver.processEnvironment(settings: settings.helperTools, locator: locator),
            timeoutSeconds: 30
        )

        let simulateTitle: String
        do {
            let result = try await simulateRunner.run(simulateRequest)
            if result.exitCode != 0 {
                throw DownloadUseCaseError.downloadFailed(Self.ytDlpFailureMessage(from: result))
            }
            let title = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            simulateTitle = title.isEmpty ? Self.fallbackJobTitle(for: url) : title
        } catch let error as DownloadUseCaseError {
            throw error
        } catch {
            throw DownloadUseCaseError.downloadFailed(error.localizedDescription)
        }

        let capturedUseCase = self
        let capturedURL = url
        let capturedOptions = options

        let job = jobRunner.enqueue(
            title: "Download: \(simulateTitle)",
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

    @discardableResult
    public func download(url: URL, options: DownloadJobOptions, progress: JobProgress) async throws -> [URL] {
        try await downloadWithRetry(url: url, options: options, progress: progress)
    }

    @discardableResult
    private func downloadWithRetry(url: URL, options: DownloadJobOptions, progress: JobProgress) async throws -> [URL] {
        var lastError: Error?

        for attempt in 0..<options.retries {
            do {
                let settings = try settingsStore.loadSettings()
                guard let ytDlpURL = healthChecker.resolvedYtDlpURL(settings: settings.helperTools) else {
                    throw DownloadUseCaseError.ytDlpUnavailable(DownloaderCopy.ytDlpMissing)
                }

                let request = DownloadRequest(
                    ytDlpURL: ytDlpURL,
                    sourceURL: url,
                    outputDirectory: options.outputDirectory,
                    outputTemplate: options.fileNameTemplate,
                    formatSelection: options.formatSelection,
                    ffmpegLocationURL: DownloaderHelperToolResolver.ffmpegLocationURL(settings: settings.helperTools, locator: locator),
                    helperSearchDirectories: DownloaderHelperToolResolver.helperSearchDirectories(settings: settings.helperTools, locator: locator),
                    playlistMode: options.playlistMode
                )

                let result = try await downloader.download(request) { line in
                    progress.log(line)
                    if let progressPct = Self.parseProgress(from: line) {
                        progress.update(progress: progressPct, message: nil)
                    }
                }

                if result.exitCode != 0 {
                    let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw DownloadUseCaseError.downloadFailed(
                        message.isEmpty ? "yt-dlp exited with code \(result.exitCode)." : message
                    )
                }

                if result.outputURLs.isEmpty {
                    throw DownloadUseCaseError.outputNotFound
                }

                progress.setOutputFileURLs(result.outputURLs)
                for outputURL in result.outputURLs {
                    progress.log("Output file: \(outputURL.path)")
                }
                progress.update(progress: 1, message: "Downloaded")

                return result.outputURLs
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

    static func parseProgress(from line: String) -> Double? {
        DownloaderProgressParsing.parseNormalizedProgress(from: line)
    }

    static func isRetryableForTesting(error: Error) -> Bool {
        isRetryable(error: error)
    }

    private static func isRetryable(error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        let retryablePatterns = [
            "http error 403",
            "http error 5",
            "connection reset",
            "connection timed out",
            "timed out",
            "socket timeout",
            "read timed out",
            "temporary failure",
            "timeout",
            "errno 54",
            "errno 60",
        ]
        return retryablePatterns.contains { message.contains($0) }
    }

    private static func fallbackJobTitle(for url: URL) -> String {
        let path = url.path
        if path == "/watch" || path.isEmpty || url.lastPathComponent == "watch" {
            return url.host ?? "media"
        }
        return url.lastPathComponent
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
