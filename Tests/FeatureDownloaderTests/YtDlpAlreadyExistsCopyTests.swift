@testable import FeatureDownloader
import Foundation
import XCTest

/// NMH-141 (TOOL-30): yt-dlp `--no-overwrites` skip must read as an
/// informational inbox status, not a generic network failure.
/// String/unit only; no network.
final class YtDlpAlreadyExistsCopyTests: XCTestCase {
    func testAlreadyExistsCopyString() {
        XCTAssertEqual(
            DownloaderCopy.alreadyExistsInInbox,
            "This file already exists in the Output Inbox."
        )
    }

    func testAlreadyDownloadedLineMapsToInboxCopy() {
        XCTAssertEqual(
            YtDlpDownloader.alreadyExistsCopy(
                for: "[download] /tmp/out/Some Title [abc123].mp4 has already been downloaded"
            ),
            DownloaderCopy.alreadyExistsInInbox
        )
        XCTAssertNil(
            YtDlpDownloader.alreadyExistsCopy(
                for: "[download]  42.5% of 10.00MiB at 1.00MiB/s ETA 00:05"
            )
        )
    }

    func testAlreadyDownloadedMarkerDetection() {
        XCTAssertTrue(
            YtDlpDownloader.containsAlreadyDownloadedMarker(
                "[download] relative/final.mp4 has already been downloaded"
            )
        )
        XCTAssertFalse(
            YtDlpDownloader.containsAlreadyDownloadedMarker(
                "[download] Destination: /tmp/out/final.mp4"
            )
        )
    }

    @MainActor
    func testViewModelDetectsSkipFromLogs() {
        XCTAssertTrue(
            DownloaderViewModel.isAlreadyDownloadedSkip(
                logEntries: ["[download] /tmp/out/Title [abc].mp4 has already been downloaded"],
                message: "No output files found after download."
            )
        )
        XCTAssertFalse(
            DownloaderViewModel.isAlreadyDownloadedSkip(
                logEntries: ["ERROR: unable to download video data: HTTP Error 403: Forbidden"],
                message: "Download failed: ERROR: unable to download video data: HTTP Error 403: Forbidden"
            )
        )
    }

    // D1: marker alone is not sufficient; verification requires an existing
    // regular file within the output root. Fake marker paths with real
    // disposable files: valid, absent, directory, outside, symlink escape.
    @MainActor
    func testVerifiedOutputsRequireExistingRegularContainedFile() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("already-exists-verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let valid = outputDir.appendingPathComponent("valid-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: valid.path, contents: Data("x".utf8))

        let validOutputs = DownloaderViewModel.verifiedAlreadyDownloadedOutputs(
            logEntries: ["[download] \(valid.path) has already been downloaded"],
            message: "No output files found after download.",
            outputDirectory: outputDir
        )
        XCTAssertEqual(validOutputs, [valid.standardizedFileURL])

        let missing = outputDir.appendingPathComponent("missing-\(UUID().uuidString).mp4")
        XCTAssertTrue(DownloaderViewModel.verifiedAlreadyDownloadedOutputs(
            logEntries: ["[download] \(missing.path) has already been downloaded"],
            message: "No output files found after download.",
            outputDirectory: outputDir
        ).isEmpty, "absent path must not verify")

        let subdir = outputDir.appendingPathComponent("subdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        XCTAssertTrue(DownloaderViewModel.verifiedAlreadyDownloadedOutputs(
            logEntries: ["[download] \(subdir.path) has already been downloaded"],
            message: "No output files found after download.",
            outputDirectory: outputDir
        ).isEmpty, "directory must not verify")

        // Arbitrary non-marker logs never verify, even when they name a real file.
        XCTAssertTrue(DownloaderViewModel.verifiedAlreadyDownloadedOutputs(
            logEntries: ["[download] Destination: \(valid.path)"],
            message: "No output files found after download.",
            outputDirectory: outputDir
        ).isEmpty, "non-marker log paths must not verify")
    }

    @MainActor
    func testVerifiedOutputsRejectOutsideAndSymlinkEscape() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("already-exists-outside-\(UUID().uuidString)", isDirectory: true)
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("already-exists-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }
        let outsideFile = outsideDir.appendingPathComponent("outside-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: outsideFile.path, contents: Data("x".utf8))
        XCTAssertTrue(DownloaderViewModel.verifiedAlreadyDownloadedOutputs(
            logEntries: ["[download] \(outsideFile.path) has already been downloaded"],
            message: "No output files found after download.",
            outputDirectory: outputDir
        ).isEmpty, "outside path must not verify")

        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("already-exists-link-\(UUID().uuidString)", isDirectory: true)
        let linkOutput = baseDir.appendingPathComponent("output", isDirectory: true)
        let linkOutside = baseDir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: linkOutput, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkOutside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let secret = linkOutside.appendingPathComponent("secret-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: secret.path, contents: Data("x".utf8))
        let linkURL = linkOutput.appendingPathComponent("link")
        do {
            try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: linkOutside.path)
        } catch {
            throw XCTSkip("Symlinks are not supported on this platform.")
        }
        let escape = linkURL.appendingPathComponent(secret.lastPathComponent).path
        XCTAssertTrue(DownloaderViewModel.verifiedAlreadyDownloadedOutputs(
            logEntries: ["[download] \(escape) has already been downloaded"],
            message: "No output files found after download.",
            outputDirectory: linkOutput
        ).isEmpty, "symlink escape must not verify")
    }

    func testVerifiedAlreadyDownloadedOutputHelper() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("already-exists-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let valid = outputDir.appendingPathComponent("valid-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: valid.path, contents: Data("x".utf8))
        XCTAssertEqual(
            YtDlpDownloader.verifiedAlreadyDownloadedOutput(for: valid.path, in: outputDir),
            valid.standardizedFileURL
        )
        XCTAssertNil(YtDlpDownloader.verifiedAlreadyDownloadedOutput(for: "", in: outputDir))
        XCTAssertNil(YtDlpDownloader.verifiedAlreadyDownloadedOutput(for: "~/\(valid.lastPathComponent)", in: outputDir))
        XCTAssertNil(YtDlpDownloader.verifiedAlreadyDownloadedOutput(
            for: outputDir.appendingPathComponent("missing-\(UUID().uuidString).mp4").path,
            in: outputDir
        ))
    }

    // D1: outcome contract — a real ERROR alongside a marker must stay a failure.
    @MainActor
    func testRealErrorDetectionForMixedMarkerAndFailure() {
        XCTAssertFalse(DownloaderViewModel.hasRealDownloadError(
            logEntries: ["[download] /tmp/out/a.mp4 has already been downloaded"],
            message: "No output files found after download."
        ))
        XCTAssertTrue(DownloaderViewModel.hasRealDownloadError(
            logEntries: [
                "[download] /tmp/out/a.mp4 has already been downloaded",
                "ERROR: unable to download video data: HTTP Error 403: Forbidden",
            ],
            message: "Download failed: ERROR: unable to download video data: HTTP Error 403: Forbidden"
        ))
    }
}
