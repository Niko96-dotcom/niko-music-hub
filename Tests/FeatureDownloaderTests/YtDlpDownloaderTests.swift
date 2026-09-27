import AppCore
import Darwin
@testable import FeatureDownloader
import XCTest

final class YtDlpDownloaderTests: XCTestCase {
    func testNonZeroExitKeepsTypedFailureWithoutOutputs() async throws {
        let downloader = YtDlpDownloader(runner: NonZeroExitRunner())
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertEqual(result.exitCode, 1)
        let failure = try XCTUnwrap(result.failure)
        XCTAssertEqual(failure.kind, .processFailed)
        XCTAssertFalse(failure.isRetryable)
        XCTAssertTrue(result.outputs.isEmpty)
        XCTAssertTrue(result.outputURLs.isEmpty)
    }

    func testNonZeroExitWithEmptyStderrFallsBackToExitCodeMessage() async throws {
        let downloader = YtDlpDownloader(runner: SilentNonZeroExitRunner())
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory
        )
        let result = try await downloader.download(request) { _ in }
        let failure = try XCTUnwrap(result.failure)
        XCTAssertEqual(failure.message, "yt-dlp exited with code 3.")
        XCTAssertFalse(failure.isRetryable)
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

    func testStreamingDownloadReportsProgressAndFindsOutputAfterItExists() async throws {        let outputURL = FileManager.default.temporaryDirectory
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
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.outputURLs, [outputURL])
        XCTAssertEqual(result.freshOutputURLs, [outputURL])
        XCTAssertTrue(result.alreadyExistingOutputURLs.isEmpty)
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
        } catch let DownloadError.failed(failure) {
            XCTAssertEqual(failure.kind, .downloadStalled)
            XCTAssertFalse(failure.isRetryable)
            XCTAssertTrue(failure.message.contains("Download stalled — no progress for 2 minutes"))
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
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.outputURLs, [fileURL.standardizedFileURL])
        XCTAssertEqual(result.alreadyExistingOutputURLs, [fileURL.standardizedFileURL])
        XCTAssertTrue(result.freshOutputURLs.isEmpty)
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
        XCTAssertTrue(YtDlpDownloader.verifiedCollectedOutputs(
            [YtDlpCollectedOutput(url: fifoURL, isAlreadyExisting: true)],
            in: outputDir
        ).isEmpty)
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

    // Typed partial playlist: one fresh file plus one verified pre-existing
    // skip, followed by a 403 failure. Both stay exposed with provenance and
    // the run stays failed but retryable.
    func testPartialPlaylistKeepsFreshAndExistingOutputsAsRetryableFailure() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-partial-mixed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let existingURL = outputDir.appendingPathComponent("existing-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data("x".utf8))
        let freshURL = outputDir.appendingPathComponent("fresh-\(UUID().uuidString).mp4")
        let runner = MixedPlaylistFailureRunner(existingPath: existingURL.path, freshURL: freshURL)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com/playlist?list=abc")!,
            outputDirectory: outputDir
        )

        let result = try await downloader.download(request) { _ in }

        XCTAssertEqual(result.exitCode, 1)
        let failure = try XCTUnwrap(result.failure)
        XCTAssertEqual(failure.kind, .processFailed)
        XCTAssertTrue(failure.isRetryable)
        XCTAssertTrue(failure.message.contains("HTTP Error 403"))
        XCTAssertEqual(Set(result.outputURLs), Set([existingURL.standardizedFileURL, freshURL.standardizedFileURL]))
        XCTAssertEqual(result.freshOutputURLs, [freshURL.standardizedFileURL])
        XCTAssertEqual(result.alreadyExistingOutputURLs, [existingURL.standardizedFileURL])
        XCTAssertEqual(Set(failure.outputs.map(\.url)), Set(result.outputURLs))
    }

    func testMarkerAloneWithoutVerifiedFileNeverProducesOutputs() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-marker-only-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let missing = outputDir.appendingPathComponent("ghost-\(UUID().uuidString).mp4")
        let runner = AlreadyDownloadedRunner(markerPath: missing.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertNil(result.failure)
        XCTAssertTrue(result.outputs.isEmpty)
    }

    func testPartialScratchMarkersNeverPropagateAsOutputs() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-scratch-\(UUID().uuidString)", isDirectory: true)
        let scratchDir = outputDir.appendingPathComponent(".nmh-partial-leftover", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let scratchFile = scratchDir.appendingPathComponent("fragment-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: scratchFile.path, contents: Data("x".utf8))
        let runner = AlreadyDownloadedRunner(markerPath: scratchFile.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        XCTAssertTrue(result.outputs.isEmpty, ".nmh-partial files must never verify")
        XCTAssertTrue(YtDlpDownloader.isPartialScratchURL(scratchFile))
        XCTAssertFalse(YtDlpDownloader.isPartialScratchURL(outputDir.appendingPathComponent("final.mp4")))
    }

    func testTimedOutProcessErrorStaysRetryableWithSalvagedOutputs() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-timedout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let finishedURL = outputDir.appendingPathComponent("finished-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: finishedURL.path, contents: Data("x".utf8))
        let runner = TimedOutAfterMarkerRunner(markerPath: finishedURL.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        do {
            _ = try await downloader.download(request) { _ in }
            XCTFail("Expected a typed timeout failure")
        } catch let DownloadError.failed(failure) {
            XCTAssertEqual(failure.kind, .processFailed)
            XCTAssertTrue(failure.isRetryable)
            XCTAssertEqual(failure.outputs.map(\.url), [finishedURL.standardizedFileURL])
        }
    }

    func testStallSalvagesCompletedEarlierPlaylistItem() async throws {
        let clock = FakeDownloadStallClock(start: Date())
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-stall-salvage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let finishedURL = outputDir.appendingPathComponent("item1-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: finishedURL.path, contents: Data("x".utf8))
        let runner = MarkerThenHangRunner(markerPath: finishedURL.path)
        let downloader = YtDlpDownloader(
            runner: runner,
            stallClock: clock,
            stallCheckIntervalNanoseconds: 10_000_000
        )
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com/playlist?list=abc")!,
            outputDirectory: outputDir
        )
        let task = Task {
            try await downloader.download(request) { _ in }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        clock.advance(by: 121)
        do {
            _ = try await task.value
            XCTFail("Expected stall failure")
        } catch let DownloadError.failed(failure) {
            XCTAssertEqual(failure.kind, .downloadStalled)
            XCTAssertFalse(failure.isRetryable)
            XCTAssertEqual(failure.outputs.map(\.url), [finishedURL.standardizedFileURL])
        }
    }

    func testCancellationAfterPartialOutputPreservesCancelAndCleansScratch() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-cancel-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let finishedURL = outputDir.appendingPathComponent("item1-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: finishedURL.path, contents: Data("x".utf8))
        let runner = MarkerThenHangRunner(markerPath: finishedURL.path)
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com/playlist?list=abc")!,
            outputDirectory: outputDir
        )
        let task = Task {
            try await downloader.download(request) { _ in }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation keeps cancel semantics.
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        XCTAssertTrue(remaining.filter { $0.hasPrefix(".nmh-partial-") }.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finishedURL.path))
    }

    func testCollectorLimitMapsToTypedNonRetryableFailure() {
        let outputDir = FileManager.default.temporaryDirectory
        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        let mapped = YtDlpDownloader.typedFailure(
            from: YtDlpOutputCollectorError.candidateLimitExceeded(maximum: 2),
            collector: collector
        )
        guard case let DownloadError.failed(failure) = mapped else {
            XCTFail("Expected typed collector-limit failure, got \(mapped)")
            return
        }
        XCTAssertEqual(failure.kind, .outputLimitExceeded)
        XCTAssertFalse(failure.isRetryable)
    }

    func testExternalRetryableSignals() {
        XCTAssertTrue(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden",
            standardOutput: ""
        ))
        XCTAssertTrue(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "ERROR: read timed out",
            standardOutput: ""
        ))
        XCTAssertTrue(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "",
            standardOutput: "ERROR: HTTP Error 500: Internal Server Error"
        ))
        XCTAssertTrue(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "",
            standardOutput: "ERROR: read timed out"
        ))
        XCTAssertFalse(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "ERROR: [youtube] abc: Video unavailable",
            standardOutput: ""
        ))
        XCTAssertFalse(YtDlpDownloader.isRetryableExternalOutput(standardError: "", standardOutput: ""))
        // Stdout paths/titles/progress never retry, even with timeout-like words.
        XCTAssertFalse(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "",
            standardOutput: "[download] Destination: /fixture/Timeout [id].mp4"
        ))
        XCTAssertFalse(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "",
            standardOutput: "[download]  45.2% of 10.0MiB at 1.0MiB/s ETA 00:05"
        ))
        XCTAssertFalse(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "",
            standardOutput: "[download] Destination: /tmp/my ERROR: song.mp4"
        ))
        // Permanent stderr stays non-retryable even with a timeout path on stdout.
        XCTAssertFalse(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "ERROR: [youtube] abc: Video unavailable",
            standardOutput: "[download] Destination: /fixture/Timeout [id].mp4"
        ))
    }

    func testPermanentStderrWithStdoutTimeoutPathIsNotRetryable() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-permanent-timeout-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let downloader = YtDlpDownloader(runner: PermanentStderrTimeoutPathRunner())
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        let failure = try XCTUnwrap(result.failure)
        XCTAssertFalse(failure.isRetryable)
        XCTAssertTrue(failure.message.contains("Video unavailable"))
    }

    func testEmptyStderrWithProgressStdoutUsesExitCodeSentence() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-progress-banner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let progressStdout = (0..<200).map { _ in "[download]  45.2% of 10.0MiB at 1.0MiB/s ETA 00:05" }
            .joined(separator: "\n") + "\n[download] Destination: /tmp/final-\(UUID().uuidString).mp4\n"
        let downloader = YtDlpDownloader(runner: ProgressStdoutFailureRunner(stdout: progressStdout, exitCode: 1))
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        let failure = try XCTUnwrap(result.failure)
        XCTAssertEqual(failure.message, "yt-dlp exited with code 1.")
        XCTAssertFalse(failure.isRetryable)
    }

    func testStdoutErrorDiagnosticIsSingleLineAndRetryable() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-stdout-error-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let stdout = [
            "[download] Destination: /tmp/final.mp4",
            "[download]  45.2% of 10.0MiB at 1.0MiB/s ETA 00:05",
            "ERROR: read timed out",
            "[download] Destination: /tmp/other.mp4",
        ].joined(separator: "\n") + "\n"
        let downloader = YtDlpDownloader(runner: ProgressStdoutFailureRunner(stdout: stdout, exitCode: 1))
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: outputDir
        )
        let result = try await downloader.download(request) { _ in }
        let failure = try XCTUnwrap(result.failure)
        XCTAssertEqual(failure.message, "ERROR: read timed out")
        XCTAssertTrue(failure.isRetryable)
    }

    func testPathWithEmbeddedErrorMarkerIsNotDiagnostic() {
        XCTAssertEqual(YtDlpDownloader.errorDiagnosticLines(from: "[download] Destination: /tmp/my ERROR: song.mp4"), [])
        XCTAssertEqual(YtDlpDownloader.errorDiagnosticLines(from: "[download] Destination: /fixture/Timeout [id].mp4"), [])
        XCTAssertEqual(
            YtDlpDownloader.errorDiagnosticLines(from: "[download]  45.2% of 10.0MiB at 1.0MiB/s"),
            []
        )
        XCTAssertEqual(
            YtDlpDownloader.errorDiagnosticLines(from: "ERROR: read timed out"),
            ["ERROR: read timed out"]
        )
        XCTAssertFalse(YtDlpDownloader.isRetryableExternalOutput(
            standardError: "",
            standardOutput: "[download] Destination: /tmp/my ERROR: song.mp4"
        ))
    }

    func testDownloadResultInitIsFailClosedForNonzeroExitWithoutFailure() {
        let outputURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).mp4")
        let outputs = [VerifiedDownloadOutput(url: outputURL, isAlreadyExisting: false)]
        let result = DownloadResult(
            outputs: outputs,
            sourceURL: URL(string: "https://example.com")!,
            exitCode: 1,
            standardError: "",
            failure: nil
        )
        XCTAssertNotNil(result.failure)
        XCTAssertEqual(result.failure?.kind, .processFailed)
        XCTAssertEqual(result.failure?.isRetryable, false)
        XCTAssertEqual(result.failure?.outputs, outputs)
    }

    func testFreshDestinationLinesAreFreshButFinalPathPrintsAreNeutral() {
        XCTAssertTrue(YtDlpDownloader.isFreshDestinationLine("[download] Destination: /tmp/a.mp4"))
        XCTAssertTrue(YtDlpDownloader.isFreshDestinationLine("[ExtractAudio] Destination: /tmp/a.wav"))
        XCTAssertTrue(YtDlpDownloader.isFreshDestinationLine("[Merger] Merging formats into \"/tmp/a.mp4\""))
        XCTAssertTrue(YtDlpDownloader.isFreshDestinationLine("[MoveFiles] Moving file \"a.part\" to \"b.mp4\""))
        XCTAssertFalse(YtDlpDownloader.isFreshDestinationLine("NIKO_MUSIC_HUB_FILE:/tmp/a.mp4"))
        XCTAssertFalse(YtDlpDownloader.isFreshDestinationLine("[download] /tmp/a.mp4 has already been downloaded"))
        XCTAssertTrue(YtDlpDownloader.isAlreadyDownloadedMarkerLine("[download] /tmp/a.mp4 has already been downloaded"))
        XCTAssertFalse(YtDlpDownloader.isAlreadyDownloadedMarkerLine("NIKO_MUSIC_HUB_FILE:/tmp/a.mp4"))
    }

    func testResolvedScratchSymlinkNeverVerifiesButContainedSymlinkDoes() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp-scratch-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let scratchDir = outputDir.appendingPathComponent(".nmh-partial-other", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        let scratchFile = scratchDir.appendingPathComponent("fragment-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: scratchFile.path, contents: Data("partial".utf8))
        let linkToScratch = outputDir.appendingPathComponent("link-scratch-\(UUID().uuidString).mp4")
        let realFile = outputDir.appendingPathComponent("real-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: realFile.path, contents: Data("done".utf8))
        let allowedLink = outputDir.appendingPathComponent("link-allowed-\(UUID().uuidString).mp4")
        do {
            try FileManager.default.createSymbolicLink(atPath: linkToScratch.path, withDestinationPath: scratchFile.path)
            try FileManager.default.createSymbolicLink(atPath: allowedLink.path, withDestinationPath: realFile.path)
        } catch {
            throw XCTSkip("Symlinks are not supported on this platform.")
        }
        // Lexical link path has no scratch component, but resolved does.
        XCTAssertFalse(YtDlpDownloader.isPartialScratchURL(linkToScratch.standardizedFileURL))
        XCTAssertTrue(YtDlpDownloader.isPartialScratchURL(scratchFile.standardizedFileURL))
        XCTAssertTrue(YtDlpDownloader.verifiedCollectedOutputs(
            [YtDlpCollectedOutput(url: linkToScratch, isAlreadyExisting: false)],
            in: outputDir
        ).isEmpty, "contained symlink to scratch must never verify")
        let allowed = YtDlpDownloader.verifiedCollectedOutputs(
            [YtDlpCollectedOutput(url: allowedLink, isAlreadyExisting: false)],
            in: outputDir
        )
        XCTAssertEqual(allowed.map(\.url), [allowedLink.standardizedFileURL])
    }
}

private struct NonZeroExitRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: 1, standardOutput: "", standardError: "ERROR")
    }
}

private struct SilentNonZeroExitRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: 3, standardOutput: "", standardError: "")
    }
}

private struct PermanentStderrTimeoutPathRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(
            exitCode: 1,
            standardOutput: "[download] Destination: /fixture/Timeout [id].mp4\n",
            standardError: "ERROR: [youtube] abc: Video unavailable"
        )
    }
}

private struct ProgressStdoutFailureRunner: ExternalProcessRunning {
    let stdout: String
    let exitCode: Int32

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: exitCode, standardOutput: stdout, standardError: "")
    }
}

private struct MixedPlaylistFailureRunner: ExternalProcessRunning {
    let existingPath: String
    let freshURL: URL

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        FileManager.default.createFile(atPath: freshURL.path, contents: Data("download".utf8))
        return .init(
            exitCode: 1,
            standardOutput: [
                "[download] \(existingPath) has already been downloaded",
                "NIKO_MUSIC_HUB_FILE:\(freshURL.path)",
            ].joined(separator: "\n") + "\n",
            standardError: "ERROR: unable to download video data: HTTP Error 403: Forbidden"
        )
    }
}

private struct TimedOutAfterMarkerRunner: StreamingExternalProcessRunning {
    let markerPath: String

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        onStandardOutput("NIKO_MUSIC_HUB_FILE:\(markerPath)\n")
        throw ExternalProcessError.timedOut(
            executable: request.executableURL.path,
            seconds: 30
        )
    }
}

private final class MarkerThenHangRunner: StreamingExternalProcessRunning, @unchecked Sendable {
    let markerPath: String

    init(markerPath: String) {
        self.markerPath = markerPath
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try await run(request, onStandardOutput: { _ in }, onStandardError: { _ in })
    }

    func run(
        _ request: ExternalProcessRequest,
        onStandardOutput: @escaping @Sendable (String) -> Void,
        onStandardError: @escaping @Sendable (String) -> Void
    ) async throws -> ExternalProcessResult {
        onStandardOutput("NIKO_MUSIC_HUB_FILE:\(markerPath)\n")
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CancellationError()
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
