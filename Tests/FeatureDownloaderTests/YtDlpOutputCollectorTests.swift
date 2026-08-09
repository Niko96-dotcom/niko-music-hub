@testable import FeatureDownloader
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
}
