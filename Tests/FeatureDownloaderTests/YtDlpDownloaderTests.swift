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
        let outputFlagIndex = try XCTUnwrap(arguments.firstIndex(of: "-o"))
        XCTAssertTrue(arguments[outputFlagIndex + 1].contains("%(id)s"))
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

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
