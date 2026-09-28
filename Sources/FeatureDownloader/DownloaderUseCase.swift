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
    /// Typed external failure from the adapter contract (kind, retryability,
    /// and kept verified outputs travel in the payload; never parsed text).
    case failed(DownloadFailure)
    /// Pure skip: only verified pre-existing outputs, nothing newly written.
    case alreadyDownloaded
    case outputNotFound
    /// Retry exited 0 with zero outputs after an earlier attempt produced
    /// verified files; those files stay published on the job.
    case retryProducedNoOutput

    public var errorDescription: String? {
        switch self {
        case let .ytDlpUnavailable(message):
            return "yt-dlp is required. \(message)"
        case let .unsupportedURL(message):
            return "This URL is not supported or yt-dlp could not access it. \(message)"
        case let .failed(failure):
            return "Download failed: \(failure.message)"
        case .alreadyDownloaded:
            return DownloaderCopy.alreadyExistsInInbox
        case .outputNotFound:
            return "No output files found after download."
        case .retryProducedNoOutput:
            return "The retry finished without new files. Files from the earlier attempt were kept."
        }
    }
}

extension DownloadUseCaseError: JobFailureReasonProviding {
    public var jobFailureReason: JobFailureReason? {
        switch self {
        case .ytDlpUnavailable:
            // Downloader-tool-specific helper signal; Stems demucs setup keys
            // only on `helperUnavailable`.
            return .downloaderHelperUnavailable
        case .alreadyDownloaded:
            return .downloadAlreadyExists
        case .failed, .unsupportedURL, .outputNotFound, .retryProducedNoOutput:
            return nil
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
                throw DownloadUseCaseError.failed(DownloadFailure(
                    kind: .processFailed,
                    message: Self.ytDlpFailureMessage(from: result),
                    isRetryable: false,
                    outputs: []
                ))
            }
            let title = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            simulateTitle = title.isEmpty ? Self.fallbackJobTitle(for: url) : title
        } catch let error as DownloadUseCaseError {
            throw error
        } catch {
            if error is CancellationError {
                throw error
            }
            throw DownloadUseCaseError.failed(DownloadFailure(
                kind: .processFailed,
                message: error.localizedDescription,
                isRetryable: false,
                outputs: []
            ))
        }

        let capturedUseCase = self
        let capturedURL = url
        let capturedOptions = options

        let job = jobRunner.enqueue(
            title: "Download: \(simulateTitle)",
            sourceToolID: ToolFeatureID("downloader")
        ) { progress in
            let result = try await capturedUseCase.downloadResultWithRetry(
                url: capturedURL,
                options: capturedOptions,
                progress: progress
            )
            // Terminal Download-pane presentation only: an all-existing typed
            // outcome surfaces as the Job's informational skip reason.
            // Direct download() below returns these URLs as success instead.
            if result.freshOutputURLs.isEmpty, !result.alreadyExistingOutputURLs.isEmpty {
                throw DownloadUseCaseError.alreadyDownloaded
            }
            progress.update(progress: 1, message: "Downloaded")
        }

        return job
    }

    /// Direct download for programmatic consumers (e.g. Stems): pre-existing
    /// verified outputs return as success so the workflow continues. Never
    /// throws `alreadyDownloaded`; that mapping lives only in the
    /// `simulateAndEnqueue` Job closure above.
    @discardableResult
    public func download(url: URL, options: DownloadJobOptions, progress: JobProgress) async throws -> [URL] {
        let result = try await downloadResultWithRetry(url: url, options: options, progress: progress)
        return result.outputURLs
    }

    /// Typed retry core: accumulates deduped verified outputs (fresh wins)
    /// across attempts, retains them on final failure, and returns the typed
    /// outcome. Callers map provenance to presentation.
    private func downloadResultWithRetry(url: URL, options: DownloadJobOptions, progress: JobProgress) async throws -> DownloadResult {
        var accumulated: [VerifiedDownloadOutput] = []
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

                // Fail-closed: nonzero exit can never be success, even when a
                // custom conformer returns nil failure. No presentation-text
                // retry inference: conservative non-retryable.
                let effectiveFailure: DownloadFailure? = {
                    if let failure = result.failure { return failure }
                    if result.exitCode != 0 {
                        let trimmed = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = trimmed.isEmpty
                            ? "yt-dlp exited with code \(result.exitCode)."
                            : trimmed
                        return DownloadFailure(
                            kind: .processFailed,
                            message: message,
                            isRetryable: false,
                            outputs: result.outputs
                        )
                    }
                    return nil
                }()

                // Accumulate across attempts so a retryable failure that
                // produced a good file never loses it to a later empty
                // attempt. Fresh provenance wins (a later skip of the same
                // file stays fresh).
                accumulated = Self.mergingAccumulated(accumulated, with: result.outputs)
                Self.publishVerifiedOutputs(accumulated, progress: progress)

                // Typed adapter outcome: verified outputs are kept on the
                // (failed) job even when the run did not fully succeed, so a
                // partial playlist still exposes completed items.
                if let failure = effectiveFailure {
                    var merged = failure
                    merged.outputs = accumulated
                    throw DownloadUseCaseError.failed(merged)
                }

                // Success requires verified outputs from the current attempt:
                // an earlier retryable attempt may have produced outputs, but a
                // final exit-0 with zero outputs must still fail (previously an
                // empty final output meant failure). Accumulated outputs were
                // already published, so the failed Job keeps them. With
                // accumulated outputs the failure names the kept retry files
                // instead of claiming none were found.
                if result.outputs.isEmpty {
                    throw accumulated.isEmpty
                        ? DownloadUseCaseError.outputNotFound
                        : DownloadUseCaseError.retryProducedNoOutput
                }

                // Success returns only the current attempt's outputs, in
                // order, so a later format is not shadowed by an earlier
                // attempt's file. Fresh provenance wins per path so an
                // earlier fresh write is not re-reported as a pure skip.
                let freshPaths = Set(accumulated.filter { !$0.isAlreadyExisting }.map { $0.url.standardizedFileURL.path })
                let currentOutputs = result.outputs.map { output -> VerifiedDownloadOutput in
                    if output.isAlreadyExisting, freshPaths.contains(output.url.standardizedFileURL.path) {
                        return VerifiedDownloadOutput(url: output.url, isAlreadyExisting: false)
                    }
                    return output
                }

                return DownloadResult(
                    outputs: currentOutputs,
                    sourceURL: url,
                    exitCode: result.exitCode,
                    standardError: result.standardError,
                    failure: nil
                )
            } catch {
                // Adapter-thrown typed failures carry salvaged verified
                // outputs; merge them so the failed job keeps partial
                // playlist success. Cancellation propagates unchanged.
                if error is CancellationError {
                    throw error
                }
                let normalized: Error
                if let downloadError = error as? DownloadError,
                   case let .failed(failure) = downloadError {
                    accumulated = Self.mergingAccumulated(accumulated, with: failure.outputs)
                    Self.publishVerifiedOutputs(accumulated, progress: progress)
                    var merged = failure
                    merged.outputs = accumulated
                    normalized = DownloadUseCaseError.failed(merged)
                } else if let useCaseError = error as? DownloadUseCaseError,
                          case let .failed(failure) = useCaseError {
                    accumulated = Self.mergingAccumulated(accumulated, with: failure.outputs)
                    Self.publishVerifiedOutputs(accumulated, progress: progress)
                    var merged = failure
                    merged.outputs = accumulated
                    normalized = DownloadUseCaseError.failed(merged)
                } else {
                    normalized = error
                }
                lastError = normalized

                if !Self.isRetryable(error: normalized) {
                    throw normalized
                }

                if attempt < options.retries - 1 {
                    let backoffSeconds = pow(2.0, Double(attempt + 1))
                    progress.log("Retry \(attempt + 2)/\(options.retries) in \(Int(backoffSeconds))s...")
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                }
            }
        }

        throw lastError ?? DownloadUseCaseError.failed(DownloadFailure(
            kind: .processFailed,
            message: "Unknown error after \(options.retries) retries",
            isRetryable: false,
            outputs: accumulated
        ))
    }

    /// Deduped merge keyed by standardized path; fresh wins so a later skip
    /// of the same file never downgrades an earlier fresh write (and vice
    /// versa an earlier skip upgraded by a later fresh write).
    private static func mergingAccumulated(
        _ base: [VerifiedDownloadOutput],
        with additional: [VerifiedDownloadOutput]
    ) -> [VerifiedDownloadOutput] {
        var ordered = base
        var indexByKey: [String: Int] = [:]
        for (index, output) in ordered.enumerated() {
            indexByKey[output.url.standardizedFileURL.path] = index
        }
        for output in additional {
            let key = output.url.standardizedFileURL.path
            if let index = indexByKey[key] {
                if ordered[index].isAlreadyExisting, !output.isAlreadyExisting {
                    ordered[index] = VerifiedDownloadOutput(
                        url: ordered[index].url,
                        isAlreadyExisting: false
                    )
                }
            } else {
                indexByKey[key] = ordered.count
                ordered.append(output)
            }
        }
        return ordered
    }

    /// Publishes verified adapter outputs to the job (flat: the job carries
    /// structured URLs, provenance was already consumed for the typed policy).
    private static func publishVerifiedOutputs(_ outputs: [VerifiedDownloadOutput], progress: JobProgress) {
        let urls = outputs.map(\.url)
        progress.setOutputFileURLs(urls)
        for outputURL in urls {
            progress.log("Output file: \(outputURL.path)")
        }
    }

    static func parseProgress(from line: String) -> Double? {
        DownloaderProgressParsing.parseNormalizedProgress(from: line)
    }

    private static func isRetryable(error: Error) -> Bool {
        // Typed recovery only: retryability arrives explicitly from the
        // adapter contract. Unknown/internal messages — even ones mentioning
        // timeouts or 403s — fail closed.
        if error is CancellationError {
            return false
        }
        if let useCaseError = error as? DownloadUseCaseError {
            if case let .failed(failure) = useCaseError {
                return failure.isRetryable
            }
            return false
        }
        if let downloadError = error as? DownloadError,
           case let .failed(failure) = downloadError {
            return failure.isRetryable
        }
        return false
    }

    static func fallbackJobTitle(for url: URL) -> String {
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
