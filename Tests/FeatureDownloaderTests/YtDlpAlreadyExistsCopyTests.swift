@testable import FeatureDownloader
import Darwin
import Foundation
import XCTest

/// NMH-141 (TOOL-30): yt-dlp `--no-overwrites` skip must read as an
/// informational inbox status, not a generic network failure.
/// Adapter provenance only; no network. Presentation reads the typed
/// `VerifiedDownloadOutput.isAlreadyExisting` flag, never log text.
final class YtDlpAlreadyExistsCopyTests: XCTestCase {
    func testAlreadyExistsCopyString() {
        XCTAssertEqual(
            DownloaderCopy.alreadyExistsInInbox,
            "This file already exists in the Output Inbox."
        )
    }

    func testAlreadyDownloadedMarkerShape() {
        XCTAssertTrue(
            YtDlpDownloader.isAlreadyDownloadedMarkerLine(
                "[download] relative/final.mp4 has already been downloaded"
            )
        )
        XCTAssertFalse(
            YtDlpDownloader.isAlreadyDownloadedMarkerLine(
                "[download] Destination: /tmp/out/final.mp4"
            )
        )
        XCTAssertFalse(
            YtDlpDownloader.isAlreadyDownloadedMarkerLine(
                "NIKO_MUSIC_HUB_FILE:/tmp/out/final.mp4"
            )
        )
    }

    // Provenance passthrough: verification preserves the adapter flag for a
    // valid contained regular file and rejects everything else. Never
    // overwrites; only filters.
    func testVerifiedCollectedOutputsPreservesProvenanceForValidContainedFile() throws {
        let outputDir = try makeDisposableDirectory(prefix: "already-exists-provenance")
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let fileURL = try makeExistingFile(named: "valid-\(UUID().uuidString).mp4", in: outputDir)

        let existing = YtDlpDownloader.verifiedCollectedOutputs(
            [YtDlpCollectedOutput(url: fileURL, isAlreadyExisting: true)],
            in: outputDir
        )
        XCTAssertEqual(existing.count, 1)
        XCTAssertEqual(existing.first?.url, fileURL.standardizedFileURL)
        XCTAssertEqual(existing.first?.isAlreadyExisting, true)

        let fresh = YtDlpDownloader.verifiedCollectedOutputs(
            [YtDlpCollectedOutput(url: fileURL, isAlreadyExisting: false)],
            in: outputDir
        )
        XCTAssertEqual(fresh.count, 1)
        XCTAssertEqual(fresh.first?.url, fileURL.standardizedFileURL)
        XCTAssertEqual(fresh.first?.isAlreadyExisting, false)
    }

    // Equivalent containment coverage for the unprovenanced helper: only an
    // existing regular file inside the output root verifies.
    func testVerifiedRegularContainedOutputsRequiresExistingRegularContainedFile() throws {
        let outputDir = try makeDisposableDirectory(prefix: "already-exists-verify")
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let valid = try makeExistingFile(named: "valid-\(UUID().uuidString).mp4", in: outputDir)
        XCTAssertEqual(
            YtDlpDownloader.verifiedRegularContainedOutputs([valid], in: outputDir),
            [valid.standardizedFileURL]
        )

        let missing = outputDir.appendingPathComponent("missing-\(UUID().uuidString).mp4")
        XCTAssertTrue(
            YtDlpDownloader.verifiedRegularContainedOutputs([missing], in: outputDir).isEmpty,
            "absent path must not verify"
        )

        let subdir = outputDir.appendingPathComponent("subdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        XCTAssertTrue(
            YtDlpDownloader.verifiedRegularContainedOutputs([subdir], in: outputDir).isEmpty,
            "directory must not verify"
        )

        let outsideDir = try makeDisposableDirectory(prefix: "already-exists-out")
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let outsideFile = try makeExistingFile(named: "outside-\(UUID().uuidString).mp4", in: outsideDir)
        XCTAssertTrue(
            YtDlpDownloader.verifiedRegularContainedOutputs([outsideFile], in: outputDir).isEmpty,
            "outside path must not verify"
        )
    }

    func testVerifiedCollectedOutputsRejectsSymlinkEscapeFIFOAndScratch() throws {
        let outputDir = try makeDisposableDirectory(prefix: "already-exists-safety")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Symlink escape: link inside output root resolving outside must not verify.
        let baseDir = try makeDisposableDirectory(prefix: "already-exists-link-base")
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let linkOutput = baseDir.appendingPathComponent("output", isDirectory: true)
        let linkOutside = baseDir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: linkOutput, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkOutside, withIntermediateDirectories: true)
        let secret = try makeExistingFile(named: "secret-\(UUID().uuidString).mp4", in: linkOutside)
        let linkURL = linkOutput.appendingPathComponent("link")
        do {
            try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: linkOutside.path)
        } catch {
            throw XCTSkip("Symlinks are not supported on this platform.")
        }
        let escape = linkURL.appendingPathComponent(secret.lastPathComponent)
        XCTAssertTrue(
            YtDlpDownloader.verifiedCollectedOutputs(
                [YtDlpCollectedOutput(url: escape, isAlreadyExisting: true)],
                in: linkOutput
            ).isEmpty,
            "symlink escape must not verify"
        )

        // FIFO must not verify as a regular file.
        let fifoURL = outputDir.appendingPathComponent("pipe-\(UUID().uuidString).mp4")
        guard fifoURL.path.withCString({ mkfifo($0, 0o644) }) == 0 else {
            throw XCTSkip("mkfifo is not supported on this platform.")
        }
        XCTAssertFalse(YtDlpDownloader.isExistingRegularFile(at: fifoURL))
        XCTAssertTrue(
            YtDlpDownloader.verifiedCollectedOutputs(
                [YtDlpCollectedOutput(url: fifoURL, isAlreadyExisting: true)],
                in: outputDir
            ).isEmpty,
            "FIFO must not verify"
        )

        // Per-run scratch must never verify, even when the file exists.
        let scratchDir = outputDir.appendingPathComponent(".nmh-partial-leftover", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        let scratchFile = try makeExistingFile(named: "fragment-\(UUID().uuidString).mp4", in: scratchDir)
        XCTAssertTrue(YtDlpDownloader.isPartialScratchURL(scratchFile))
        XCTAssertTrue(
            YtDlpDownloader.verifiedCollectedOutputs(
                [YtDlpCollectedOutput(url: scratchFile, isAlreadyExisting: false)],
                in: outputDir
            ).isEmpty,
            ".nmh-partial files must never verify"
        )
    }

    // Typed result conveniences: outputURLs unions provenance, fresh/existing split it.
    func testDownloadResultProvenanceConveniences() {
        let freshURL = URL(fileURLWithPath: "/tmp/out/fresh-\(UUID().uuidString).mp4")
        let existingURL = URL(fileURLWithPath: "/tmp/out/existing-\(UUID().uuidString).mp4")
        let result = DownloadResult(
            outputs: [
                VerifiedDownloadOutput(url: freshURL, isAlreadyExisting: false),
                VerifiedDownloadOutput(url: existingURL, isAlreadyExisting: true),
            ],
            sourceURL: URL(string: "https://example.com/playlist?list=abc")!,
            exitCode: 1,
            standardError: "ERROR: [youtube] abc: Video unavailable",
            failure: DownloadFailure(
                kind: .processFailed,
                message: "ERROR: [youtube] abc: Video unavailable",
                isRetryable: false,
                outputs: [
                    VerifiedDownloadOutput(url: freshURL, isAlreadyExisting: false),
                    VerifiedDownloadOutput(url: existingURL, isAlreadyExisting: true),
                ]
            )
        )
        XCTAssertEqual(result.outputURLs, [freshURL, existingURL])
        XCTAssertEqual(result.freshOutputURLs, [freshURL])
        XCTAssertEqual(result.alreadyExistingOutputURLs, [existingURL])
    }

    // MARK: - Disposable fixtures (unique roots, always cleaned up)

    private func makeDisposableDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExistingFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("download".utf8).write(to: url)
        return url
    }
}
