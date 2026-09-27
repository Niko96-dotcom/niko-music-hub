import AppCore
import Darwin
import Foundation
import NikoMusicCore

public struct DownloadRequest: Equatable, Sendable {
    public static let defaultOutputTemplate = "%(title)s [%(id)s].%(ext)s"

    public var ytDlpURL: URL
    public var sourceURL: URL
    public var outputDirectory: URL
    public var outputTemplate: String
    public var formatSelection: DownloadFormatSelection
    public var ffmpegLocationURL: URL?
    public var helperSearchDirectories: [URL]
    public var playlistMode: DownloadPlaylistMode

    public init(
        ytDlpURL: URL,
        sourceURL: URL,
        outputDirectory: URL,
        outputTemplate: String = Self.defaultOutputTemplate,
        formatSelection: DownloadFormatSelection = .default,
        ffmpegLocationURL: URL? = nil,
        helperSearchDirectories: [URL] = [],
        playlistMode: DownloadPlaylistMode = .single
    ) {
        self.ytDlpURL = ytDlpURL
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.outputTemplate = outputTemplate
        self.formatSelection = formatSelection
        self.ffmpegLocationURL = ffmpegLocationURL
        self.helperSearchDirectories = helperSearchDirectories
        self.playlistMode = playlistMode
    }
}

/// Provenance of one verified download output. Fresh files were written by
/// this run; already-existing files were skipped by `--no-overwrites` and
/// verified as pre-existing regular files. Built only at the adapter
/// boundary; presentation policy reads this flag, never log text.
public struct VerifiedDownloadOutput: Equatable, Sendable {
    public var url: URL
    public var isAlreadyExisting: Bool

    public init(url: URL, isAlreadyExisting: Bool) {
        self.url = url
        self.isAlreadyExisting = isAlreadyExisting
    }
}

/// External failure classification. Built only at the adapter boundary from
/// raw process results and raw yt-dlp output. `message` is display-only and
/// is never parsed for recovery decisions.
public enum DownloadFailureKind: String, Equatable, Sendable {
    case processFailed
    case downloadStalled
    case postProcessingStalled
    case noOutput
    case outputLimitExceeded
}

/// One typed download outcome/failure contract. `isRetryable` is classified
/// from raw external process output at the adapter boundary; internal
/// messages never affect it. `outputs` keeps verified partial playlist
/// success on failures.
public struct DownloadFailure: Equatable, Sendable {
    public var kind: DownloadFailureKind
    public var message: String
    public var isRetryable: Bool
    public var outputs: [VerifiedDownloadOutput]

    public init(kind: DownloadFailureKind, message: String, isRetryable: Bool, outputs: [VerifiedDownloadOutput]) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
        self.outputs = outputs
    }
}

public struct DownloadResult: Equatable, Sendable {
    public var outputs: [VerifiedDownloadOutput]
    public var sourceURL: URL
    public var exitCode: Int32
    public var standardError: String
    /// Non-nil when the run did not fully succeed. Verified `outputs` are
    /// still kept (partial playlist success followed by failure or stall).
    public var failure: DownloadFailure?

    public init(
        outputs: [VerifiedDownloadOutput],
        sourceURL: URL,
        exitCode: Int32,
        standardError: String,
        failure: DownloadFailure? = nil
    ) {
        self.outputs = outputs
        self.sourceURL = sourceURL
        self.exitCode = exitCode
        self.standardError = standardError
        // Fail-closed representation: a nonzero exit can never be observed
        // as success, even when a custom DownloadRunning conformer returns
        // nil failure. No presentation-text retry inference: conservative
        // non-retryable.
        if exitCode != 0, failure == nil {
            let trimmed = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? "yt-dlp exited with code \(exitCode)." : trimmed
            self.failure = DownloadFailure(
                kind: .processFailed,
                message: message,
                isRetryable: false,
                outputs: outputs
            )
        } else {
            self.failure = failure
        }
    }

    /// All verified outputs (fresh + already-existing), never partial scratch.
    public var outputURLs: [URL] {
        outputs.map(\.url)
    }

    /// Newly written verified files.
    public var freshOutputURLs: [URL] {
        outputs.filter { !$0.isAlreadyExisting }.map(\.url)
    }

    /// Verified pre-existing skip files.
    public var alreadyExistingOutputURLs: [URL] {
        outputs.filter(\.isAlreadyExisting).map(\.url)
    }
}

public enum DownloadError: LocalizedError, Equatable, Sendable {
    case missingYtDlp
    case failed(DownloadFailure)
    case outputNotFound
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingYtDlp:
            return DownloaderCopy.missingYtDlp
        case let .failed(failure):
            return failure.message
        case .outputNotFound:
            return "No output files found after download."
        case .cancelled:
            return "Download was cancelled."
        }
    }
}

public protocol DownloadRunning: Sendable {
    func download(_ request: DownloadRequest, progressHandler: @escaping @Sendable (String) -> Void) async throws -> DownloadResult
}

public struct YtDlpDownloader: DownloadRunning {
    private let runner: any ExternalProcessRunning
    private let stallClock: any DownloadStallClock
    private let stallCheckIntervalNanoseconds: UInt64

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner(),
        stallClock: any DownloadStallClock = SystemDownloadStallClock(),
        stallCheckIntervalNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.runner = runner
        self.stallClock = stallClock
        self.stallCheckIntervalNanoseconds = stallCheckIntervalNanoseconds
    }

    public func download(_ request: DownloadRequest, progressHandler: @escaping @Sendable (String) -> Void) async throws -> DownloadResult {
        let partialDirectory = request.outputDirectory.appendingPathComponent(
            ".nmh-partial-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        do {
            // yt-dlp used to create a missing output folder itself; keep that.
            try FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: false)
        } catch {
            throw DownloadError.failed(DownloadFailure(
                kind: .processFailed,
                message: error.localizedDescription,
                isRetryable: false,
                outputs: []
            ))
        }
        let args = YtDlpDownloadCommandBuilder.downloadArguments(for: request, partialDirectory: partialDirectory)

        let processRequest = ExternalProcessRequest(
            executableURL: request.ytDlpURL,
            arguments: args,
            environment: DownloaderHelperToolResolver.processEnvironment(
                helperSearchDirectories: request.helperSearchDirectories
            ),
            timeoutSeconds: nil
        )

        let stallMonitor = DownloadStallMonitor(clock: stallClock)
        stallMonitor.recordActivity()
        let runner = self.runner
        let outputDirectory = request.outputDirectory
        let sourceURL = request.sourceURL
        let stallCheckIntervalNanoseconds = self.stallCheckIntervalNanoseconds
        // The collector lives outside the task group so thrown process/stall
        // errors can still salvage verified finished outputs (completed
        // earlier playlist items) after cancellation settles.
        let collector = YtDlpOutputCollector(
            outputDirectory: outputDirectory,
            fileManager: .default,
            progressHandler: { line in
                // Each complete line can move the phase (download ↔
                // post-processing), which picks the stall window.
                stallMonitor.recordActivity(line: line)
                progressHandler(line)
            },
            onActivity: { stallMonitor.recordActivity() }
        )
        // yt-dlp keeps .part files and un-merged fragments here; only finished files
        // move to the output folder, so removing this one folder never touches user files.
        func removePartialDirectory(reportingCleanup: Bool) {
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: partialDirectory.path)) ?? []
            try? FileManager.default.removeItem(at: partialDirectory)
            if reportingCleanup, !leftovers.isEmpty {
                progressHandler(DownloaderCopy.partialCleanup)
            }
        }

        do {
            let processResult = try await withThrowingTaskGroup(of: ExternalProcessResult.self) { group in
                group.addTask {
                    let message = try await Self.pollForStall(
                        monitor: stallMonitor,
                        intervalNanoseconds: stallCheckIntervalNanoseconds
                    )
                    let kind: DownloadFailureKind =
                        stallMonitor.phase == .downloading ? .downloadStalled : .postProcessingStalled
                    throw DownloadError.failed(DownloadFailure(
                        kind: kind,
                        message: message,
                        isRetryable: false,
                        outputs: []
                    ))
                }

                group.addTask {
                    if let streamingRunner = runner as? any StreamingExternalProcessRunning {
                        return try await streamingRunner.run(
                            processRequest,
                            onStandardOutput: { collector.consume($0) },
                            onStandardError: { collector.consume($0) }
                        )
                    } else {
                        let result = try await runner.run(processRequest)
                        collector.consume(result.standardOutput)
                        collector.consume(result.standardError)
                        return result
                    }
                }

                guard let processResult = try await group.next() else {
                    throw DownloadError.failed(DownloadFailure(
                        kind: .processFailed,
                        message: "Download did not produce a result.",
                        isRetryable: false,
                        outputs: []
                    ))
                }
                group.cancelAll()
                return processResult
            }
            removePartialDirectory(reportingCleanup: false)
            return try Self.classifiedResult(
                processResult,
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                collector: collector
            )
        } catch {
            removePartialDirectory(reportingCleanup: true)
            throw Self.typedFailure(from: error, collector: collector)
        }
    }

    private static func pollForStall(
        monitor: DownloadStallMonitor,
        intervalNanoseconds: UInt64
    ) async throws -> String {
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: intervalNanoseconds)
            if let message = monitor.stallFailureMessage() {
                return message
            }
        }
        throw CancellationError()
    }

    static func parseProgressPercentage(from line: String) -> Double? {
        DownloaderProgressParsing.parseProgressPercentage(from: line)
    }

    static func outputPathCandidates(from line: String) -> [String] {
        if line.hasPrefix("NIKO_MUSIC_HUB_FILE:") {
            let path = String(line.dropFirst("NIKO_MUSIC_HUB_FILE:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? [] : [path]
        }

        let markerPatterns = [
            #"\[download\]\s+Destination:\s+(.+)$"#,
            #"\[ExtractAudio\]\s+Destination:\s+(.+)$"#,
            #"\[Merger\]\s+Merging formats into\s+\"(.+)\""#,
            #"\[MoveFiles\]\s+Moving file\s+\".+\"\s+to\s+\"(.+)\""#,
        ]
        for pattern in markerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: line) else {
                continue
            }
            let path = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? [] : [path]
        }

        let alreadyDownloadedPattern = Self.alreadyDownloadedPattern
        if let regex = try? NSRegularExpression(pattern: alreadyDownloadedPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: line) {
            let path = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? [] : [path]
        }

        return []
    }

    /// Adapter-boundary provenance: true when this single line has the
    /// already-downloaded skip shape, so its paths tag as pre-existing.
    static func isAlreadyDownloadedMarkerLine(_ line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: alreadyDownloadedPattern) else { return false }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// Adapter-boundary provenance: true when this single line announces an
    /// actual fresh write (Destination/Merger/MoveFiles). `NIKO_MUSIC_HUB_FILE:`
    /// after_move prints are neutral final-path reports, not fresh evidence:
    /// a skip marker plus a final-path print must stay existing, while a
    /// fresh destination followed by a repeated playlist skip stays fresh
    /// (fresh wins at merge time).
    static func isFreshDestinationLine(_ line: String) -> Bool {
        if isAlreadyDownloadedMarkerLine(line) { return false }
        if line.hasPrefix("NIKO_MUSIC_HUB_FILE:") { return false }
        let freshPatterns = [
            #"\[download\]\s+Destination:\s+(.+)$"#,
            #"\[ExtractAudio\]\s+Destination:\s+(.+)$"#,
            #"\[Merger\]\s+Merging formats into\s+\"(.+)\""#,
            #"\[MoveFiles\]\s+Moving file\s+\".+\"\s+to\s+\"(.+)\""#,
        ]
        for pattern in freshPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 2,
                  Range(match.range(at: 1), in: line) != nil else {
                continue
            }
            return true
        }
        return false
    }

    private static let alreadyDownloadedPattern = #"\[download\]\s+(.+)\s+has already been downloaded"#

    /// D1: the collector already enforces containment, but it accepts any
    /// existing path. Verified propagation requires an existing regular file
    /// (not a directory) inside the intended output root, with symlink
    /// escapes rejected and per-run `.nmh-partial-*` scratch excluded.
    /// Never overwrites; only filters.
    ///
    /// Regular-file check uses `lstat`/`stat` resource types so FIFOs, devices,
    /// and sockets never verify. A symlink verifies only when its resolved
    /// target is a regular file *and* the resolved location stays contained in
    /// the output root (contained-symlink allowed, escape rejected).
    static func verifiedRegularContainedOutputs(_ urls: [URL], in outputDirectory: URL) -> [URL] {
        verifiedCollectedOutputs(
            urls.map { YtDlpCollectedOutput(url: $0, isAlreadyExisting: false) },
            in: outputDirectory
        ).map(\.url)
    }

    /// Shared adapter diagnostic extraction: only lines that are actually
    /// error-shaped (`ERROR:` at line start after trimming, case-insensitive)
    /// count as diagnostics. Output paths, titles, and progress lines never
    /// count, even when a filename embeds `ERROR:` or timeout-like words.
    static func errorDiagnosticLines(from output: String) -> [String] {
        output.components(separatedBy: .newlines).compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard trimmed.lowercased().hasPrefix("error:") else { return nil }
            return trimmed
        }
    }

    static func firstErrorDiagnosticLine(from output: String) -> String? {
        errorDiagnosticLines(from: output).first
    }

    /// Builds the typed adapter outcome from a settled process result.
    /// Verified outputs are kept even on non-zero exit (partial playlist
    /// success). Retryability is classified here from raw external output;
    /// internal messages never affect it.
    static func classifiedResult(
        _ result: ExternalProcessResult,
        sourceURL: URL,
        outputDirectory: URL,
        collector: YtDlpOutputCollector
    ) throws -> DownloadResult {
        let verified = verifiedCollectedOutputs(try collector.finishCollecting(), in: outputDirectory)
        if result.exitCode != 0 {
            let message: String = {
                let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stderr.isEmpty { return stderr }
                if let diagnostic = firstErrorDiagnosticLine(from: result.standardOutput) {
                    return diagnostic
                }
                return "yt-dlp exited with code \(result.exitCode)."
            }()
            return DownloadResult(
                outputs: verified,
                sourceURL: sourceURL,
                exitCode: result.exitCode,
                standardError: result.standardError,
                failure: DownloadFailure(
                    kind: .processFailed,
                    message: message,
                    isRetryable: isRetryableExternalOutput(
                        standardError: result.standardError,
                        standardOutput: result.standardOutput
                    ),
                    outputs: verified
                )
            )
        }
        return DownloadResult(
            outputs: verified,
            sourceURL: sourceURL,
            exitCode: result.exitCode,
            standardError: result.standardError,
            failure: nil
        )
    }

    /// Maps a thrown error to the typed contract, salvaging verified finished
    /// outputs from the still-available collector. Cancellation propagates
    /// unchanged so callers keep cancel semantics.
    static func typedFailure(from error: Error, collector: YtDlpOutputCollector) -> Error {
        if error is CancellationError {
            return error
        }
        let salvaged = salvagedVerifiedOutputs(collector: collector)
        if let downloadError = error as? DownloadError {
            switch downloadError {
            case var .failed(failure):
                if failure.outputs.isEmpty {
                    failure.outputs = salvaged
                }
                return DownloadError.failed(failure)
            case .missingYtDlp, .outputNotFound, .cancelled:
                return downloadError
            }
        }
        if let collectorError = error as? YtDlpOutputCollectorError {
            return DownloadError.failed(DownloadFailure(
                kind: .outputLimitExceeded,
                message: collectorError.errorDescription ?? "Too many yt-dlp output paths.",
                isRetryable: false,
                outputs: salvaged
            ))
        }
        // Already typed by AppCore; preserved as retryable without parsing text.
        if let processError = error as? ExternalProcessError, case .timedOut = processError {
            return DownloadError.failed(DownloadFailure(
                kind: .processFailed,
                message: processError.localizedDescription,
                isRetryable: true,
                outputs: salvaged
            ))
        }
        return DownloadError.failed(DownloadFailure(
            kind: .processFailed,
            message: error.localizedDescription,
            isRetryable: false,
            outputs: salvaged
        ))
    }

    /// Best-effort salvage after cancellation settles. Never throws.
    static func salvagedVerifiedOutputs(collector: YtDlpOutputCollector) -> [VerifiedDownloadOutput] {
        guard let collected = try? collector.finishCollecting() else { return [] }
        return verifiedCollectedOutputs(collected, in: collector.outputDirectory)
    }

    /// Provenance-preserving verification: an existing regular file (not a
    /// directory, FIFO, device, or socket) inside the intended output root,
    /// with symlink escapes rejected and per-run `.nmh-partial-*` scratch
    /// excluded. Never overwrites; only filters.
    static func verifiedCollectedOutputs(
        _ collected: [YtDlpCollectedOutput],
        in outputDirectory: URL
    ) -> [VerifiedDownloadOutput] {
        let safety = PathSafety(fileManager: .default)
        return collected.compactMap { entry in
            let standardized = entry.url.standardizedFileURL
            guard !isPartialScratchURL(standardized) else { return nil }
            // A contained symlink to scratch (e.g. output/link -> .nmh-partial-*/file)
            // passes lexical + regular + containment on the link path, but is not
            // a finished output. Filter the resolved location too; contained
            // symlinks to real finished files have no scratch component resolved.
            let resolved = standardized.resolvingSymlinksInPath()
            guard !isPartialScratchURL(resolved) else { return nil }
            guard isExistingRegularFile(at: standardized) else { return nil }
            guard safety.isResolvedContained(standardized, in: [outputDirectory]) else { return nil }
            return VerifiedDownloadOutput(url: standardized, isAlreadyExisting: entry.isAlreadyExisting)
        }
    }

    /// Per-run yt-dlp scratch (`.part` files, un-merged fragments) must never
    /// propagate as finished outputs.
    static func isPartialScratchURL(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0.hasPrefix(".nmh-partial-") }
    }

    /// Raw external failure interpretation, adapter boundary only. Preserves
    /// the intended HTTP 403 / timeout / transient retry support. Internal
    /// presentation text never reaches this function. Stderr is scanned as a
    /// whole; stdout contributes only error-shaped (`ERROR:`) diagnostic
    /// lines, never output paths, titles, or progress.
    static func isRetryableExternalOutput(standardError: String, standardOutput: String) -> Bool {
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
        let stderrText = standardError.lowercased()
        if retryablePatterns.contains(where: { stderrText.contains($0) }) {
            return true
        }
        let stdoutDiagnostics = errorDiagnosticLines(from: standardOutput)
            .joined(separator: "\n")
            .lowercased()
        guard !stdoutDiagnostics.isEmpty else { return false }
        return retryablePatterns.contains { stdoutDiagnostics.contains($0) }
    }

    /// Actual filesystem type check: only `S_IFREG` verifies. Symlinks are
    /// followed to their target; only a regular-file target verifies.
    static func isExistingRegularFile(at url: URL) -> Bool {
        var lstatInfo = stat()
        guard url.path.withCString({ Darwin.lstat($0, &lstatInfo) }) == 0 else { return false }
        let fileType = lstatInfo.st_mode & mode_t(S_IFMT)
        if fileType == mode_t(S_IFLNK) {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            var statInfo = stat()
            guard resolved.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &statInfo, 0) }) == 0 else { return false }
            return (statInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
        }
        return fileType == mode_t(S_IFREG)
    }
}
