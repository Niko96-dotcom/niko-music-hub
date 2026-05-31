import AppCore
@testable import FeatureDownloader
import XCTest

final class YtDlpDownloaderTests: XCTestCase {
    func testNoShellInvocationAppearsInSource() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureDownloader/YtDlpDownloader.swift",
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("/bin/sh"))
        XCTAssertFalse(source.contains("sh\", \"-c"))
        XCTAssertFalse(source.contains("shell"))
    }

    func testDownloadReturnsNonZeroExitCode() async throws {
        let downloader = YtDlpDownloader(runner: NonZeroExitRunner())
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertEqual(result.exitCode, 1)
    }

    func testUsesExecutableURL() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureDownloader/YtDlpDownloader.swift",
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("executableURL"))
    }

    func testDownloadAppliesBoundedNetworkRetries() async throws {
        let runner = CapturingRunner()
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        _ = try await downloader.download(request) { _ in }

        XCTAssertEqual(runner.lastRequest?.arguments.contains("--socket-timeout"), true)
        XCTAssertEqual(runner.lastRequest?.arguments.contains("--retries"), true)
        XCTAssertEqual(runner.lastRequest?.arguments.contains("--fragment-retries"), true)
        XCTAssertEqual(runner.lastRequest?.arguments.contains("--extractor-retries"), true)
        XCTAssertEqual(
            runner.lastRequest?.arguments.contains("best[height<=360][ext=mp4]/best[height<=360]/worst"),
            true
        )
        XCTAssertEqual(runner.lastRequest?.arguments.contains("-f"), true)
        XCTAssertEqual(runner.lastRequest?.timeoutSeconds, 90)
    }

    func testDownloadDoesNotForceOverwriteExistingOutputs() async throws {
        let runner = CapturingRunner()
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        _ = try await downloader.download(request) { _ in }

        let arguments = try XCTUnwrap(runner.lastRequest?.arguments)
        XCTAssertFalse(arguments.contains("--force-overwrites"))
        XCTAssertTrue(arguments.contains("--no-overwrites"))
        XCTAssertTrue(arguments.contains("--print"))
        XCTAssertTrue(arguments.contains("after_move:NIKO_MUSIC_HUB_FILE:%(filepath)s"))
        let outputFlagIndex = try XCTUnwrap(arguments.firstIndex(of: "-o"))
        XCTAssertTrue(arguments[outputFlagIndex + 1].contains("%(id)s"))
    }

    func testStreamingDownloadReportsProgressAndFindsOutputAfterItExists() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yt-dlp-stream-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let runner = StreamingDestinationRunner(outputURL: outputURL)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )
        let progressLines = LockedStringArray()

        let result = try await downloader.download(request) { line in
            progressLines.append(line)
        }

        let capturedProgress = progressLines.values()
        XCTAssertEqual(result.outputURLs, [outputURL])
        XCTAssertTrue(capturedProgress.contains { $0.contains("10.0%") })
        XCTAssertTrue(capturedProgress.contains { $0.contains("Destination:") })
    }

    func testOutputPathCandidatesCoverYtDlpFinalPathLines() {
        XCTAssertEqual(
            YtDlpDownloader.outputPathCandidates(from: "NIKO_MUSIC_HUB_FILE:/tmp/final.mp4"),
            ["/tmp/final.mp4"]
        )
        XCTAssertEqual(
            YtDlpDownloader.outputPathCandidates(from: "[ExtractAudio] Destination: /tmp/final.wav"),
            ["/tmp/final.wav"]
        )
        XCTAssertEqual(
            YtDlpDownloader.outputPathCandidates(from: "[MoveFiles] Moving file \"a.part\" to \"relative/final.mp4\""),
            ["relative/final.mp4"]
        )
        XCTAssertEqual(
            YtDlpDownloader.outputPathCandidates(from: "[download] relative/final.mp4 has already been downloaded"),
            ["relative/final.mp4"]
        )
    }
}

private final class LockedStringArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.withLock {
            storage.append(value)
        }
    }

    func values() -> [String] {
        lock.withLock {
            storage
        }
    }
}

private struct NonZeroExitRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: 1, standardOutput: "", standardError: "ERROR")
    }
}

private final class CapturingRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var request: ExternalProcessRequest?

    var lastRequest: ExternalProcessRequest? {
        lock.withLock { request }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock {
            self.request = request
        }
        return .init(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private final class StreamingDestinationRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    let outputURL: URL

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        XCTFail("Downloader should use streaming runner when available")
        return ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "")
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        onStandardOutput("[download] 10.0% of 1.0MiB at 1.0MiB/s ETA 00:01\n")
        onStandardOutput("[download] Destination: \(outputURL.path)\n")
        FileManager.default.createFile(atPath: outputURL.path, contents: Data("download".utf8))
        return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
