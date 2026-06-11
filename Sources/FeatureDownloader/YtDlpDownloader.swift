import AppCore
import Foundation

public struct DownloadRequest: Equatable, Sendable {
    public static let defaultOutputTemplate = "%(title)s [%(id)s].%(ext)s"

    public var ytDlpURL: URL
    public var sourceURL: URL
    public var outputDirectory: URL
    public var outputTemplate: String
    public var formatSelection: DownloadFormatSelection
    public var ffmpegLocationURL: URL?
    public var helperSearchDirectories: [URL]

    public init(
        ytDlpURL: URL,
        sourceURL: URL,
        outputDirectory: URL,
        outputTemplate: String = Self.defaultOutputTemplate,
        formatSelection: DownloadFormatSelection = .default,
        ffmpegLocationURL: URL? = nil,
        helperSearchDirectories: [URL] = []
    ) {
        self.ytDlpURL = ytDlpURL
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.outputTemplate = outputTemplate
        self.formatSelection = formatSelection
        self.ffmpegLocationURL = ffmpegLocationURL
        self.helperSearchDirectories = helperSearchDirectories
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
            return "yt-dlp is required. Choose yt-dlp in Settings."
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
                    try await Self.pollForStall(
                        monitor: stallMonitor,
                        intervalNanoseconds: stallCheckIntervalNanoseconds
                    )
                    throw DownloadError.downloadFailed(DownloadStallMonitor.stallErrorMessage)
                }

                group.addTask {
                    let collector = YtDlpOutputCollector(
                        outputDirectory: outputDirectory,
                        fileManager: .default,
                        progressHandler: progressHandler,
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
                    let outputURLs = collector.finish()

                    return DownloadResult(
                        outputURLs: outputURLs,
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
    ) async throws {
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: intervalNanoseconds)
            if monitor.checkStalled() {
                return
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
}
