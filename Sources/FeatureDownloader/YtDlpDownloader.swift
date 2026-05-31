import AppCore
import Foundation

public struct DownloadRequest: Equatable, Sendable {
    public static let defaultOutputTemplate = "%(title)s [%(id)s].%(ext)s"

    public var ytDlpURL: URL
    public var sourceURL: URL
    public var outputDirectory: URL
    public var outputTemplate: String
    public var formatSelection: DownloadFormatSelection

    public init(
        ytDlpURL: URL,
        sourceURL: URL,
        outputDirectory: URL,
        outputTemplate: String = Self.defaultOutputTemplate,
        formatSelection: DownloadFormatSelection = .default
    ) {
        self.ytDlpURL = ytDlpURL
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.outputTemplate = outputTemplate
        self.formatSelection = formatSelection
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

    public init(
        runner: any ExternalProcessRunning = FoundationExternalProcessRunner()
    ) {
        self.runner = runner
    }

    public func download(_ request: DownloadRequest, progressHandler: @escaping @Sendable (String) -> Void) async throws -> DownloadResult {
        let fileManager = FileManager.default
        let outputPath = request.outputDirectory.appendingPathComponent(request.outputTemplate).path

        let formatArgs = YtDlpFormatArgumentBuilder.arguments(for: request.formatSelection)
        var args: [String] = [
            "--newline",
            "--no-overwrites",
            "--socket-timeout", "30",
            "--retries", "1",
            "--fragment-retries", "1",
            "--extractor-retries", "1",
            "-f", formatArgs.formatSelector,
        ]
        args.append(contentsOf: formatArgs.extraArguments)
        args.append(contentsOf: [
            "--progress-template", "download:%progress",
            "--print", "after_move:NIKO_MUSIC_HUB_FILE:%(filepath)s",
            "-o", outputPath,
            request.sourceURL.absoluteString,
        ])

        let processRequest = ExternalProcessRequest(
            executableURL: request.ytDlpURL,
            arguments: args,
            timeoutSeconds: 90
        )

        do {
            let collector = YtDlpOutputCollector(
                outputDirectory: request.outputDirectory,
                fileManager: fileManager,
                progressHandler: progressHandler
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
                sourceURL: request.sourceURL,
                exitCode: result.exitCode,
                standardError: result.standardError
            )
        } catch {
            throw DownloadError.downloadFailed(error.localizedDescription)
        }
    }

    static func parseProgressPercentage(from line: String) -> Double? {
        guard line.contains("[download]") else { return nil }
        let pattern = "(\\d+\\.?\\d*)%"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(line[range]) else {
            return nil
        }
        return min(max(value, 0), 100)
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

private final class YtDlpOutputCollector: @unchecked Sendable {
    private let outputDirectory: URL
    private let fileManager: FileManager
    private let progressHandler: @Sendable (String) -> Void
    private let lock = NSLock()
    private var pending = ""
    private var candidatePaths: [String] = []

    init(
        outputDirectory: URL,
        fileManager: FileManager,
        progressHandler: @escaping @Sendable (String) -> Void
    ) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
        self.progressHandler = progressHandler
    }

    func consume(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        let lines = lock.withLock {
            pending += chunk
            return drainCompleteLines()
        }
        for line in lines {
            process(line)
        }
    }

    func finish() -> [URL] {
        let finalLines = lock.withLock {
            let remaining = pending
            pending = ""
            return remaining.isEmpty ? [] : [remaining]
        }
        for line in finalLines {
            process(line)
        }

        return lock.withLock {
            var resolved: [URL] = []
            for path in candidatePaths {
                for url in urls(for: path) where !resolved.contains(url) {
                    if fileManager.fileExists(atPath: url.path) {
                        resolved.append(url)
                        break
                    }
                }
            }
            return resolved
        }
    }

    private func process(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        progressHandler(trimmed)
        let paths = YtDlpDownloader.outputPathCandidates(from: trimmed)
        guard !paths.isEmpty else { return }
        lock.withLock {
            for path in paths where !candidatePaths.contains(path) {
                candidatePaths.append(path)
            }
        }
    }

    private func drainCompleteLines() -> [String] {
        var lines: [String] = []
        while let newline = pending.firstIndex(where: \.isNewline) {
            let line = String(pending[..<newline])
            lines.append(line)
            pending.removeSubrange(...newline)
        }
        return lines
    }

    private func urls(for path: String) -> [URL] {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return [URL(fileURLWithPath: expanded)]
        }
        return [
            outputDirectory.appendingPathComponent(path),
            URL(fileURLWithPath: path),
        ]
    }
}
