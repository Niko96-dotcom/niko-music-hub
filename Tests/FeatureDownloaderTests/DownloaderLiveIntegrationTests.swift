@testable import FeatureDownloader
import AppCore
import XCTest

/// Opt-in live downloader verification (UAT-02). Skipped unless `NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1`.
final class DownloaderLiveIntegrationTests: XCTestCase {
    private static let liveTestVideoURL = "https://www.youtube.com/watch?v=BaW_jenozKc"
    private static let minimumDurationSeconds = 18.0

    func testLiveDownloadEmitsProgressAndProducesOutput() async throws {
        try XCTSkipUnless(Self.isLiveDownloaderEnabled(), "Set NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1 to run live downloader tests")
        let ytDlpURL = try XCTUnwrap(Self.resolveYtDlpURL(), "yt-dlp not found on this machine")
        let ffmpegLocation = Self.resolveFfmpegLocationURL()

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloaderLiveIntegrationTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let sourceURL = URL(string: Self.liveTestVideoURL)!
        let request = DownloadRequest(
            ytDlpURL: ytDlpURL,
            sourceURL: sourceURL,
            outputDirectory: outputDirectory,
            formatSelection: DownloadFormatSelection(
                mediaKind: .audioOnly,
                audioContainer: .m4a
            ),
            ffmpegLocationURL: ffmpegLocation,
            helperSearchDirectories: Self.helperSearchDirectories(for: ytDlpURL)
        )

        let progressLines = LockedStringArray()
        let downloader = YtDlpDownloader()
        let result = try await downloader.download(request) { line in
            progressLines.append(line)
        }

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.outputURLs.isEmpty, "Expected at least one output file")
        XCTAssertTrue(
            progressLines.values().contains { $0.contains("NIKO_PROGRESS:") },
            "Expected NIKO_PROGRESS markers in live download output"
        )

        let outputURL = try XCTUnwrap(result.outputURLs.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        if let duration = try Self.mediaDurationSeconds(at: outputURL) {
            XCTAssertGreaterThan(
                duration,
                Self.minimumDurationSeconds,
                "Live download should exceed the prior 18-second happy-path clip"
            )
        } else {
            throw XCTSkip("ffprobe not available for duration check")
        }
    }

    func testLiveDownloadFailsForInvalidURL() async throws {
        try XCTSkipUnless(Self.isLiveDownloaderEnabled(), "Set NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1 to run live downloader tests")
        let ytDlpURL = try XCTUnwrap(Self.resolveYtDlpURL(), "yt-dlp not found on this machine")

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloaderLiveIntegrationTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let request = DownloadRequest(
            ytDlpURL: ytDlpURL,
            sourceURL: URL(string: "https://www.youtube.com/watch?v=invalidvideo123456789")!,
            outputDirectory: outputDirectory,
            formatSelection: DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .m4a),
            ffmpegLocationURL: Self.resolveFfmpegLocationURL(),
            helperSearchDirectories: Self.helperSearchDirectories(for: ytDlpURL)
        )

        let result = try await YtDlpDownloader().download(request) { _ in }
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.outputURLs.isEmpty)
        XCTAssertFalse(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func isLiveDownloaderEnabled() -> Bool {
        ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_LIVE_DOWNLOADER"] == "1"
    }

    private static func resolveYtDlpURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/opt/local/bin/yt-dlp"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func resolveFfmpegLocationURL() -> URL? {
        DownloaderHelperToolResolver.ffmpegLocationURL(settings: HelperToolSettings())
    }

    private static func helperSearchDirectories(for ytDlpURL: URL) -> [URL] {
        [ytDlpURL.deletingLastPathComponent()]
    }

    private static func mediaDurationSeconds(at url: URL) throws -> Double? {
        let ffprobeCandidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/opt/local/bin/ffprobe"
        ]
        guard let ffprobePath = ffprobeCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Double(text)
    }
}
