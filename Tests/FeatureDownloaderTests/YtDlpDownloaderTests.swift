import AppCore
import Darwin
@testable import FeatureDownloader
import XCTest

final class YtDlpDownloaderTests: XCTestCase {
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

    func testInvokesConfiguredExecutableWithURLAsSingleArgument() async throws {
        let runner = CapturingRunner()
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/tmp/helper tools/yt-dlp"),
            sourceURL: URL(string: "https://example.com/watch?v=abc&list=xyz")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )

        _ = try await downloader.download(request) { _ in }

        let invocation = try XCTUnwrap(runner.lastRequest)
        XCTAssertEqual(invocation.executableURL, request.ytDlpURL)
        XCTAssertEqual(invocation.arguments.last, request.sourceURL.absoluteString)
        XCTAssertFalse(invocation.arguments.contains("-c"))
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
        XCTAssertEqual(runner.lastRequest?.arguments.contains("--progress-template"), true)
        XCTAssertEqual(runner.lastRequest?.arguments.contains("--no-playlist"), true)
        XCTAssertTrue(runner.lastRequest?.arguments.contains(YtDlpDownloadCommandBuilder.progressTemplate) ?? false)
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

    // D1: verified propagation with fake runner and real disposable files.
    func testAlreadyDownloadedValidExistingPathReturnsVerifiedOutput() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-valid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let fileURL = outputDir.appendingPathComponent("existing-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))
        let runner = AlreadyDownloadedRunner(markerPath: fileURL.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertEqual(result.outputURLs, [fileURL.standardizedFileURL])
    }

    func testAlreadyDownloadedAbsentPathReturnsEmpty() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-absent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let missing = outputDir.appendingPathComponent("missing-\(UUID().uuidString).mp4")
        let runner = AlreadyDownloadedRunner(markerPath: missing.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertTrue(result.outputURLs.isEmpty)
    }

    func testAlreadyDownloadedDirectoryReturnsEmpty() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let subdir = outputDir.appendingPathComponent("subdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let runner = AlreadyDownloadedRunner(markerPath: subdir.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertTrue(result.outputURLs.isEmpty, "directories must not propagate as outputs")
    }

    func testAlreadyDownloadedOutsidePathReturnsEmpty() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-inside-\(UUID().uuidString)", isDirectory: true)
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }
        let outsideFile = outsideDir.appendingPathComponent("outside-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: outsideFile.path, contents: Data("x".utf8))
        let runner = AlreadyDownloadedRunner(markerPath: outsideFile.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertTrue(result.outputURLs.isEmpty, "uncontained log paths must not propagate")
    }

    func testAlreadyDownloadedSymlinkEscapeReturnsEmpty() async throws {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-symlink-\(UUID().uuidString)", isDirectory: true)
        let outputDir = baseDir.appendingPathComponent("output", isDirectory: true)
        let outsideDir = baseDir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let outsideFile = outsideDir.appendingPathComponent("secret-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: outsideFile.path, contents: Data("x".utf8))
        let linkURL = outputDir.appendingPathComponent("link")
        do {
            try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: outsideDir.path)
        } catch {
            throw XCTSkip("Symlinks are not supported on this platform.")
        }
        let escapePath = linkURL.appendingPathComponent(outsideFile.lastPathComponent).path
        let runner = AlreadyDownloadedRunner(markerPath: escapePath)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertTrue(result.outputURLs.isEmpty, "symlink escapes must not propagate")
    }

    func testVerifiedRegularContainedOutputsRejectsDirectory() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let subdir = outputDir.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        XCTAssertTrue(YtDlpDownloader.verifiedRegularContainedOutputs([subdir], in: outputDir).isEmpty)
    }

    // D1: FIFO/device/socket must not verify as regular files (lstat type check).
    func testVerifiedRegularContainedOutputsRejectsFIFO() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-fifo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let fifoURL = outputDir.appendingPathComponent("pipe-\(UUID().uuidString).mp4")
        guard fifoURL.path.withCString({ mkfifo($0, 0o644) }) == 0 else {
            throw XCTSkip("mkfifo is not supported on this platform.")
        }
        XCTAssertFalse(YtDlpDownloader.isExistingRegularFile(at: fifoURL))
        XCTAssertTrue(YtDlpDownloader.verifiedRegularContainedOutputs([fifoURL], in: outputDir).isEmpty)
        XCTAssertNil(YtDlpDownloader.verifiedAlreadyDownloadedOutput(for: fifoURL.path, in: outputDir))
    }

    func testDownloadRoutesPartialsToPerRunTempDirectory() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-partial-args-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let runner = CapturingRunner()
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )

        _ = try await downloader.download(request) { _ in }

        let arguments = try XCTUnwrap(runner.lastRequest?.arguments)
        let pathValues = arguments.indices.filter { arguments[$0] == "-P" }.map { arguments[$0 + 1] }
        XCTAssertEqual(pathValues.count, 2)
        XCTAssertTrue(pathValues.contains("home:\(outputDir.path)"))
        let tempValue = try XCTUnwrap(pathValues.first(where: { $0.hasPrefix("temp:") }))
        let tempURL = URL(fileURLWithPath: String(tempValue.dropFirst("temp:".count)))
        XCTAssertEqual(tempURL.deletingLastPathComponent().path, outputDir.path)
        XCTAssertTrue(tempURL.lastPathComponent.hasPrefix(".nmh-partial-"))
        let outputFlagIndex = try XCTUnwrap(arguments.firstIndex(of: "-o"))
        XCTAssertEqual(arguments[outputFlagIndex + 1], "%(title)s [%(id)s].%(ext)s")
        XCTAssertTrue(arguments[outputFlagIndex + 1].contains("%(id)s"))
    }

    func testFailedDownloadCleansUpPartialDirectoryAndKeepsUnrelatedFiles() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-partial-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let keepURL = outputDir.appendingPathComponent("keep.txt")
        FileManager.default.createFile(atPath: keepURL.path, contents: Data("keep".utf8))
        let runner = PartialWritingCancellationRunner()
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let messages = LockedStringArray()
        do {
            _ = try await downloader.download(request) { messages.append($0) }
            XCTFail("Expected download to throw")
        } catch {
            // Expected: cancellation surfaces as a thrown download error.
        }

        let arguments = try XCTUnwrap(runner.lastRequest?.arguments)
        let tempValue = try XCTUnwrap(arguments.indices.filter { arguments[$0] == "-P" }.map { arguments[$0 + 1] }.first(where: { $0.hasPrefix("temp:") }))
        let tempPath = String(tempValue.dropFirst("temp:".count))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        XCTAssertTrue(remaining.filter { $0.hasPrefix(".nmh-partial-") }.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepURL.path))
        XCTAssertEqual(messages.values().filter { $0 == DownloaderCopy.partialCleanup }.count, 1)
    }

    func testSuccessfulDownloadRemovesPartialDirectoryAndKeepsFinalOutput() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-partial-success-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let finalURL = outputDir.appendingPathComponent("final-\(UUID().uuidString).mp4")
        let runner = PartialSuccessRunner(outputFileURL: finalURL)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )

        let result = try await downloader.download(request) { _ in }

        XCTAssertEqual(result.outputURLs, [finalURL.standardizedFileURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
        let arguments = try XCTUnwrap(runner.lastRequest?.arguments)
        let tempValue = try XCTUnwrap(arguments.indices.filter { arguments[$0] == "-P" }.map { arguments[$0 + 1] }.first(where: { $0.hasPrefix("temp:") }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: String(tempValue.dropFirst("temp:".count))))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        XCTAssertTrue(remaining.filter { $0.hasPrefix(".nmh-partial-") }.isEmpty)
    }
}

private struct NonZeroExitRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: 1, standardOutput: "", standardError: "ERROR")
    }
}

private struct AlreadyDownloadedRunner: ExternalProcessRunning {
    let markerPath: String

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: 0, standardOutput: "[download] \(markerPath) has already been downloaded\n", standardError: "")
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

private final class PartialWritingCancellationRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var request: ExternalProcessRequest?

    var lastRequest: ExternalProcessRequest? {
        lock.withLock { request }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock {
            self.request = request
        }
        for index in request.arguments.indices where request.arguments[index] == "-P" {
            guard index + 1 < request.arguments.count else { continue }
            let value = request.arguments[index + 1]
            guard value.hasPrefix("temp:") else { continue }
            let partialURL = URL(fileURLWithPath: String(value.dropFirst("temp:".count)), isDirectory: true)
            FileManager.default.createFile(
                atPath: partialURL.appendingPathComponent("x.part").path,
                contents: Data("partial".utf8)
            )
        }
        throw CancellationError()
    }
}

private final class PartialSuccessRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var request: ExternalProcessRequest?
    let outputFileURL: URL

    init(outputFileURL: URL) {
        self.outputFileURL = outputFileURL
    }

    var lastRequest: ExternalProcessRequest? {
        lock.withLock { request }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock {
            self.request = request
        }
        FileManager.default.createFile(atPath: outputFileURL.path, contents: Data("download".utf8))
        return .init(exitCode: 0, standardOutput: "NIKO_MUSIC_HUB_FILE:\(outputFileURL.path)\n", standardError: "")
    }
}
