@testable import FeatureDownloader
import Foundation
import XCTest

final class YtDlpOutputCollectorTests: XCTestCase {
    func testSplitUTF8AcrossChunksReassemblesLine() {
        let outputDir = FileManager.default.temporaryDirectory
        let progressLines = LockedStringArray()
        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { progressLines.append($0) }
        )
        let emoji = "café"
        let line = "\(emoji) progress\n"
        let data = Data(line.utf8)
        let splitIndex = data.index(data.startIndex, offsetBy: 3)
        let first = String(decoding: data[..<splitIndex], as: UTF8.self)
        let second = String(decoding: data[splitIndex...], as: UTF8.self)

        collector.consume(first)
        collector.consume(second)

        let lines = progressLines.values()
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines.first?.contains(emoji) ?? false)
    }

    func testSplitFileMarkerAcrossChunks() throws {
        let outputDir = FileManager.default.temporaryDirectory
        let fileURL = outputDir.appendingPathComponent("split-marker-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let marker = "NIKO_MUSIC_HUB_FILE:\(fileURL.path)"
        let splitIndex = marker.index(marker.startIndex, offsetBy: marker.count / 2)
        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )

        collector.consume(String(marker[..<splitIndex]))
        collector.consume(String(marker[splitIndex...]) + "\n")

        let urls = try collector.finish()
        XCTAssertEqual(urls, [fileURL])
    }

    func testFinishProcessesUnterminatedMarkerWithoutWholeOutputReplay() throws {
        let outputDir = FileManager.default.temporaryDirectory
        let fileURL = outputDir.appendingPathComponent("reparse-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:\(fileURL.path)")

        let urls = try collector.finish()
        XCTAssertEqual(urls, [fileURL])
    }

    func testOversizedUnterminatedLineIsDiscardedWithoutLogging() throws {
        let progressLines = LockedStringArray()
        let collector = YtDlpOutputCollector(
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            fileManager: .default,
            progressHandler: { progressLines.append($0) },
            maximumPendingLineBytes: 32
        )

        collector.consume(String(repeating: "x", count: 33))

        XCTAssertTrue(progressLines.values().isEmpty)
        XCTAssertTrue(try collector.finish().isEmpty)
        XCTAssertTrue(progressLines.values().isEmpty)
    }

    func testOversizedLineIsDiscardedThenFollowingMarkerResolves() throws {
        let outputDir = URL(fileURLWithPath: "/tmp")
        let fileURL = outputDir.appendingPathComponent("collector-recovery-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let progressLines = LockedStringArray()
        let marker = "NIKO_MUSIC_HUB_FILE:\(fileURL.path)"
        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { progressLines.append($0) },
            maximumPendingLineBytes: 128
        )

        collector.consume(String(repeating: "x", count: 129))
        collector.consume("\n\(marker)\n")

        XCTAssertEqual(try collector.finish(), [fileURL])
        XCTAssertEqual(progressLines.values(), [marker])
    }

    func testCandidateOverflowFailsExplicitlyAndReportsIt() throws {
        let outputDir = URL(fileURLWithPath: "/tmp")
        let fileURLs = (0..<3).map {
            outputDir.appendingPathComponent("collector-candidate-\($0)-\(UUID().uuidString).mp4")
        }
        defer {
            for fileURL in fileURLs {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        for fileURL in fileURLs {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))
        }

        let progressLines = LockedStringArray()
        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { progressLines.append($0) },
            maximumCandidatePaths: 2
        )

        for fileURL in fileURLs {
            collector.consume("NIKO_MUSIC_HUB_FILE:\(fileURL.path)\n")
        }

        XCTAssertThrowsError(try collector.finish()) { error in
            XCTAssertEqual(
                error as? YtDlpOutputCollectorError,
                .candidateLimitExceeded(maximum: 2)
            )
        }
        XCTAssertTrue(progressLines.values().contains(
            "Output path detection limit reached; additional paths were ignored."
        ))
    }

    func testNonASCIIPathInMarker() throws {
        let outputDir = FileManager.default.temporaryDirectory
        let fileURL = outputDir.appendingPathComponent("音楽-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:\(fileURL.path)\n")

        XCTAssertEqual(try collector.finish(), [fileURL])
    }

    func testAbsolutePathInsideOutputDirectoryIsAccepted() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-inside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let fileURL = outputDir.appendingPathComponent("track-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:\(fileURL.path)\n")

        XCTAssertEqual(try collector.finish(), [fileURL.standardizedFileURL])
    }

    func testRelativePathInsideOutputDirectoryIsAccepted() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-relative-\(UUID().uuidString)", isDirectory: true)
        let subdir = outputDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let fileName = "track-\(UUID().uuidString).mp4"
        let fileURL = subdir.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:sub/\(fileName)\n")

        XCTAssertEqual(try collector.finish(), [fileURL.standardizedFileURL])
    }

    func testAbsolutePathOutsideOutputDirectoryIsRejected() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-output-\(UUID().uuidString)", isDirectory: true)
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }
        let outsideFile = outsideDir.appendingPathComponent("unrelated-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: outsideFile.path, contents: Data("x".utf8))

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:\(outsideFile.path)\n")

        XCTAssertTrue(try collector.finish().isEmpty)
    }

    func testDotDotEscapeIsRejected() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-dotdot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let outsideFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-escape-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outsideFile) }
        FileManager.default.createFile(atPath: outsideFile.path, contents: Data("x".utf8))

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        // Relative `..` that standardizes outside the output directory.
        collector.consume("NIKO_MUSIC_HUB_FILE:../\(outsideFile.lastPathComponent)\n")

        XCTAssertTrue(try collector.finish().isEmpty)
    }

    func testTildePathIsRejected() throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let fileName = "collector-tilde-\(UUID().uuidString).mp4"
        let homeFile = homeDir.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: homeFile.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: homeFile) }
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-tilde-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:~/\(fileName)\n")

        XCTAssertTrue(try collector.finish().isEmpty)
    }

    func testSiblingPrefixIsRejected() throws {
        let baseName = "collector-prefix-\(UUID().uuidString)"
        let barDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName, isDirectory: true)
        let evilDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName + "-evil", isDirectory: true)
        try FileManager.default.createDirectory(at: barDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evilDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: barDir)
            try? FileManager.default.removeItem(at: evilDir)
        }
        let evilFile = evilDir.appendingPathComponent("track-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: evilFile.path, contents: Data("x".utf8))

        let collector = YtDlpOutputCollector(
            outputDirectory: barDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:\(evilFile.path)\n")

        XCTAssertTrue(try collector.finish().isEmpty)
    }

    func testSymlinkEscapeIsRejected() throws {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-symlink-\(UUID().uuidString)", isDirectory: true)
        let outputDir = baseDir.appendingPathComponent("output", isDirectory: true)
        let outsideDir = baseDir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let outsideFile = outsideDir.appendingPathComponent("secret-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: outsideFile.path, contents: Data("x".utf8))
        let linkURL = outputDir.appendingPathComponent("link")
        do {
            try FileManager.default.createSymbolicLink(
                atPath: linkURL.path,
                withDestinationPath: outsideDir.path
            )
        } catch {
            throw XCTSkip("Symlinks are not supported on this platform.")
        }

        let absoluteCollector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        absoluteCollector.consume("NIKO_MUSIC_HUB_FILE:\(linkURL.appendingPathComponent(outsideFile.lastPathComponent).path)\n")
        XCTAssertTrue(try absoluteCollector.finish().isEmpty)

        let relativeCollector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        relativeCollector.consume("NIKO_MUSIC_HUB_FILE:link/\(outsideFile.lastPathComponent)\n")
        XCTAssertTrue(try relativeCollector.finish().isEmpty)
    }

    func testProcessCWDFallbackStaysRemoved() throws {
        let fileName = "collector-cwd-\(UUID().uuidString).mp4"
        let cwdFileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: cwdFileURL.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: cwdFileURL) }
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("collector-cwd-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let collector = YtDlpOutputCollector(
            outputDirectory: outputDir,
            fileManager: .default,
            progressHandler: { _ in }
        )
        collector.consume("NIKO_MUSIC_HUB_FILE:\(fileName)\n")

        XCTAssertTrue(try collector.finish().isEmpty)
    }
}
