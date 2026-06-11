@testable import FeatureDownloader
import AppCore
import XCTest

/// Traceability matrix for v1.4 downloader UAT (UAT-01).
final class DownloaderUATCoverageTests: XCTestCase {
    func testProgressMarkerParsingIsCovered() throws {
        let progress = try XCTUnwrap(
            DownloaderProgressParsing.parseNormalizedProgress(from: "NIKO_PROGRESS: 42.5%")
        )
        XCTAssertEqual(progress, 0.425, accuracy: 0.0001)
        XCTAssertEqual(
            YtDlpDownloadCommandBuilder.progressTemplate,
            "NIKO_PROGRESS:%(progress)s"
        )
    }

    func testStallPolicyIsCovered() {
        let clock = FakeDownloadStallClock(start: Date(timeIntervalSince1970: 0))
        let monitor = DownloadStallMonitor(clock: clock)
        monitor.recordActivity()
        clock.advance(by: 119)
        XCTAssertFalse(monitor.checkStalled())
        clock.advance(by: 1)
        XCTAssertTrue(monitor.checkStalled())
        XCTAssertEqual(
            DownloadStallMonitor.stallErrorMessage,
            "Download stalled — no progress for 2 minutes"
        )
    }

    func testHelperHealthStatesAreRepresented() async {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = HelperToolSettings(ytDlp: URL(fileURLWithPath: "/usr/local/bin/yt-dlp"))
        let checker = YtDlpHealthChecker(
            runner: UATVersionRunner(output: "2024.01.01\n"),
            fileExists: { _ in true },
            referenceDate: reference
        )
        if case .outdated = await checker.availability(settings: settings) {
            // expected stale path
        } else {
            XCTFail("Expected outdated helper classification")
        }
    }

    func testStructuredOutputContractIsRepresented() {
        let outputURL = URL(fileURLWithPath: "/tmp/out/track.m4a")
        let result = DownloadResult(
            outputURLs: [outputURL],
            sourceURL: URL(string: "https://example.com/watch?v=test")!,
            exitCode: 0,
            standardError: ""
        )
        XCTAssertEqual(result.outputURLs, [outputURL])
        XCTAssertEqual(
            YtDlpDownloadCommandBuilder.filePrintMarker,
            "after_move:NIKO_MUSIC_HUB_FILE:%(filepath)s"
        )
    }

    func testMediaHandoffAllowlistIsCovered() throws {
        let mp3 = try makeTempFile(named: "song.mp3")
        let downloaderItem = OutputInboxItem(
            fileURL: mp3,
            sourceToolID: "downloader",
            status: .available
        )
        XCTAssertTrue(OutputHandoff.isRevealable(downloaderItem))
        XCTAssertTrue(OutputHandoff.isDragReady(downloaderItem))

        let wav = try makeTempFile(named: "take.wav")
        let converterItem = OutputInboxItem(
            fileURL: wav,
            sourceToolID: "wav-converter",
            status: .available
        )
        XCTAssertTrue(OutputHandoff.isDragReady(converterItem))
    }

    private func makeTempFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: url)
        return url
    }
}

private struct UATVersionRunner: ExternalProcessRunning {
    let output: String

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        ExternalProcessResult(exitCode: 0, standardOutput: output, standardError: "")
    }
}
