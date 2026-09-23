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

public struct DownloadResult: Equatable, Sendable {
    public var outputURLs: [URL]
    public var sourceURL: URL
    public var exitCode: Int32
    public var standardError: String

    public init(
        outputURLs: [URL],
        sourceURL: URL,
        exitCode: Int32,
        standardError: String
    ) {
        self.outputURLs = outputURLs
        self.sourceURL = sourceURL
        self.exitCode = exitCode
        self.standardError = standardError
    }
}

public enum DownloadError: LocalizedError, Equatable, Sendable {
    case missingYtDlp
    case downloadFailed(String)
    case outputNotFound
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingYtDlp:
            return DownloaderCopy.missingYtDlp
        case .downloadFailed(let message):
            return "Download failed: \(message)"
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
        let args = YtDlpDownloadCommandBuilder.downloadArguments(for: request)

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

        do {
            return try await withThrowingTaskGroup(of: DownloadResult.self) { group in
                group.addTask {
                    let message = try await Self.pollForStall(
                        monitor: stallMonitor,
                        intervalNanoseconds: stallCheckIntervalNanoseconds
                    )
                    throw DownloadError.downloadFailed(message)
                }

                group.addTask {
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
                    let result: ExternalProcessResult
                    if let streamingRunner = runner as? any StreamingExternalProcessRunning {
                        result = try await streamingRunner.run(
                            processRequest,
                            onStandardOutput: { collector.consume($0) },
                            onStandardError: { collector.consume($0) }
                        )
                    } else {
                        result = try await runner.run(processRequest)
                        collector.consume(result.standardOutput)
                        collector.consume(result.standardError)
                    }
                    let outputURLs = try collector.finish()
                    let verifiedOutputs = Self.verifiedRegularContainedOutputs(outputURLs, in: outputDirectory)

                    return DownloadResult(
                        outputURLs: verifiedOutputs,
                        sourceURL: sourceURL,
                        exitCode: result.exitCode,
                        standardError: result.standardError
                    )
                }

                guard let downloadResult = try await group.next() else {
                    throw DownloadError.downloadFailed("Download did not produce a result.")
                }
                group.cancelAll()
                return downloadResult
            }
        } catch let error as DownloadError {
            throw error
        } catch {
            throw DownloadError.downloadFailed(error.localizedDescription)
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

        let alreadyDownloadedPattern = #"\[download\]\s+(.+)\s+has already been downloaded"#
        if let regex = try? NSRegularExpression(pattern: alreadyDownloadedPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: line) {
            let path = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? [] : [path]
        }

        return []
    }

    /// NMH-141 (TOOL-30): yt-dlp prints "[download] <path> has already been
    /// downloaded" when `--no-overwrites` skips an existing file. Detecting
    /// the marker lets the UI explain the skip instead of showing a generic
    /// network failure. `--no-overwrites` itself is unchanged (NMH-102).
    static func containsAlreadyDownloadedMarker(_ text: String) -> Bool {
        text.contains("has already been downloaded")
    }

    /// Maps an already-downloaded yt-dlp line to the inbox status copy.
    /// Returns nil for unrelated lines.
    static func alreadyExistsCopy(for line: String) -> String? {
        containsAlreadyDownloadedMarker(line) ? DownloaderCopy.alreadyExistsInInbox : nil
    }

    /// D1: the collector already enforces containment, but it accepts any
    /// existing path. Verified propagation requires an existing regular file
    /// (not a directory) inside the intended output root, with symlink
    /// escapes rejected. Never overwrites; only filters.
    ///
    /// Regular-file check uses `lstat`/`stat` resource types so FIFOs, devices,
    /// and sockets never verify. A symlink verifies only when its resolved
    /// target is a regular file *and* the resolved location stays contained in
    /// the output root (contained-symlink allowed, escape rejected).
    static func verifiedRegularContainedOutputs(_ urls: [URL], in outputDirectory: URL) -> [URL] {
        let safety = PathSafety(fileManager: .default)
        return urls.filter { url in
            let standardized = url.standardizedFileURL
            guard isExistingRegularFile(at: standardized) else { return false }
            return safety.isResolvedContained(standardized, in: [outputDirectory])
        }
    }

    /// D1: resolve an already-downloaded marker path to a verified regular
    /// file within the intended output root. Relative paths resolve only
    /// beneath the output directory; absolute paths must already be contained.
    /// Tilde, empty, absent, directory, FIFO/device/socket, outside, and
    /// symlink-escape paths return nil. No file is created or overwritten.
    static func verifiedAlreadyDownloadedOutput(for path: String, in outputDirectory: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("~") else { return nil }
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path)
        } else {
            candidate = outputDirectory.appendingPathComponent(path)
        }
        let standardized = candidate.standardizedFileURL
        guard isExistingRegularFile(at: standardized) else { return nil }
        let safety = PathSafety(fileManager: .default)
        guard safety.isResolvedContained(standardized, in: [outputDirectory]) else { return nil }
        return standardized
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
