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
        XCTAssertNil(runner.lastRequest?.timeoutSeconds)
        XCTAssertEqual(runner.lastRequest?.arguments.contains("--progress"), true)
        XCTAssertEqual(runner.lastRequest?.arguments.contains("--no-playlist"), true)
        XCTAssertTrue(runner.lastRequest?.arguments.contains(YtDlpDownloadCommandBuilder.progressTemplate) ?? false)
    }

    func testDownloadEmitsNIKOProgressTemplate() async throws {
        let runner = CapturingRunner()
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        _ = try await downloader.download(request) { _ in }

        let arguments = try XCTUnwrap(runner.lastRequest?.arguments)
        XCTAssertTrue(arguments.contains("--progress"))
        XCTAssertTrue(arguments.contains("--progress-template"))
        XCTAssertTrue(arguments.contains(YtDlpDownloadCommandBuilder.progressTemplate))
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
        XCTAssertTrue(capturedProgress.contains { $0.contains("NIKO_PROGRESS:") })
        XCTAssertTrue(capturedProgress.contains { $0.contains("NIKO_MUSIC_HUB_FILE:") })
    }

    func testStallAfterSilenceFailsWithLockedMessage() async throws {
        let clock = FakeDownloadStallClock(start: Date())
        let runner = SilentStreamingRunner()
        let downloader = YtDlpDownloader(
            runner: runner,
            stallClock: clock,
            stallCheckIntervalNanoseconds: 10_000_000
        )
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        let task = Task {
            try await downloader.download(request) { _ in }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        clock.advance(by: 121)
        do {
            _ = try await task.value
            XCTFail("Expected stall failure")
        } catch let error as DownloadError {
            guard case let .downloadFailed(message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(message.contains("Download stalled — no progress for 2 minutes"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProgressResetsStallClock() async throws {
        let clock = FakeDownloadStallClock(start: Date())
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stall-reset-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let runner = DelayedProgressStreamingRunner(outputURL: outputURL, clock: clock)
        let downloader = YtDlpDownloader(
            runner: runner,
            stallClock: clock,
            stallCheckIntervalNanoseconds: 10_000_000
        )
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        let result = try await downloader.download(request) { _ in }
        XCTAssertEqual(result.outputURLs, [outputURL])
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

private final class SilentStreamingRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CancellationError()
    }
}

private final class DelayedProgressStreamingRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    let outputURL: URL
    let clock: FakeDownloadStallClock

    init(outputURL: URL, clock: FakeDownloadStallClock) {
        self.outputURL = outputURL
        self.clock = clock
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        clock.advance(by: 60)
        onStandardOutput("NIKO_PROGRESS: 5.0%\n")
        onStandardOutput("NIKO_MUSIC_HUB_FILE:\(outputURL.path)\n")
        FileManager.default.createFile(atPath: outputURL.path, contents: Data("download".utf8))
        return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
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
        onStandardOutput("NIKO_PROGRESS: 10.0%\n")
        onStandardOutput("NIKO_MUSIC_HUB_FILE:\(outputURL.path)\n")
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
