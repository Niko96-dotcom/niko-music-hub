import AppCore
import Foundation

public struct DownloadRequest: Equatable, Sendable {
    public var ytDlpURL: URL
    public var sourceURL: URL
    public var outputDirectory: URL
    public var outputTemplate: String
    public var formatSelection: DownloadFormatSelection

    public init(
        ytDlpURL: URL,
        sourceURL: URL,
        outputDirectory: URL,
        outputTemplate: String = "%(title)s.%(ext)s",
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
            "--force-overwrites",
            "--socket-timeout", "30",
            "--retries", "1",
            "--fragment-retries", "1",
            "--extractor-retries", "1",
            "-f", formatArgs.formatSelector,
        ]
        args.append(contentsOf: formatArgs.extraArguments)
        args.append(contentsOf: [
            "--progress-template", "download:%progress",
            "-o", outputPath,
            request.sourceURL.absoluteString,
        ])

        let processRequest = ExternalProcessRequest(
            executableURL: request.ytDlpURL,
            arguments: args,
            timeoutSeconds: 90
        )

        do {
            let result = try await runner.run(processRequest)

            var outputURLs: [URL] = []
            let lines = result.standardOutput.split(whereSeparator: \.isNewline)
            for line in lines {
                let str = String(line)
                progressHandler(str)

                if str.contains("[download] Destination:") {
                    let pathPart = str.components(separatedBy: "Destination:").last?.trimmingCharacters(in: .whitespaces) ?? ""
                    if !pathPart.isEmpty {
                        let parsedURL = URL(fileURLWithPath: pathPart)
                        // yt-dlp may show absolute or relative paths in Destination line
                        let candidates = [parsedURL, request.outputDirectory.appendingPathComponent(pathPart)]
                        for url in candidates where !outputURLs.contains(url) {
                            if fileManager.fileExists(atPath: url.path) {
                                outputURLs.append(url)
                                break
                            }
                        }
                    }
                }

                if str.contains("[Merger] Merging formats into") {
                    if let quotedRange = str.range(of: "\"(.*)\"", options: .regularExpression) {
                        let quotedPath = String(str[quotedRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        let fileURL = URL(fileURLWithPath: quotedPath)
                        if fileURL.path.hasPrefix("/") || fileURL.path.hasPrefix("~") {
                            if fileManager.fileExists(atPath: fileURL.path) {
                                outputURLs.append(fileURL)
                            }
                        } else {
                            let mergedURL = request.outputDirectory.appendingPathComponent(quotedPath)
                            if fileManager.fileExists(atPath: mergedURL.path) {
                                outputURLs.append(mergedURL)
                            }
                        }
                    }
                }

            }

            if outputURLs.isEmpty && result.exitCode == 0 {
                if let first = lines.first(where: { String($0).contains("[download]") }) {
                    let str = String(first)
                    if let destIdx = str.range(of: "Destination:") {
                        let pathPart = str[destIdx.upperBound...].trimmingCharacters(in: .whitespaces)
                        let relativeURL = URL(fileURLWithPath: String(pathPart))
                        let absoluteURL = request.outputDirectory.appendingPathComponent(pathPart)
                        if fileManager.fileExists(atPath: absoluteURL.path) {
                            outputURLs.append(absoluteURL)
                        } else if fileManager.fileExists(atPath: relativeURL.path) {
                            outputURLs.append(relativeURL)
                        }
                    }
                }
            }

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
}
