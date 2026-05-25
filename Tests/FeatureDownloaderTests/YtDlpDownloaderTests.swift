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
}

private struct NonZeroExitRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        .init(exitCode: 1, standardOutput: "", standardError: "ERROR")
    }
}
