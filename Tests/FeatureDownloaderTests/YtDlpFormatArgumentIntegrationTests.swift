import AppCore
@testable import FeatureDownloader
import XCTest

final class YtDlpFormatArgumentIntegrationTests: XCTestCase {
    func testDownloadPassesAudioFormatFlagsToYtDlp() async throws {
        let runner = CapturingRunner()
        let downloader = YtDlpDownloader(runner: runner)
        let request = DownloadRequest(
            ytDlpURL: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            sourceURL: URL(string: "https://example.com")!,
            outputDirectory: FileManager.default.temporaryDirectory,
            formatSelection: DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .mp3)
        )

        _ = try await downloader.download(request) { _ in }

        let arguments = try XCTUnwrap(runner.lastRequest?.arguments)
        XCTAssertTrue(arguments.contains("--extract-audio"))
        XCTAssertTrue(arguments.contains("--audio-format"))
        XCTAssertTrue(arguments.contains("mp3"))
        XCTAssertTrue(arguments.contains("bestaudio/best"))
    }
}

private final class CapturingRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var request: ExternalProcessRequest?

    var lastRequest: ExternalProcessRequest? {
        lock.withLock { request }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { self.request = request }
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
