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

        let urls = collector.finish()
        XCTAssertEqual(urls, [fileURL])
    }

    func testFinishReparsesAccumulatedMarkerMissedDuringStreaming() throws {
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

        let urls = collector.finish()
        XCTAssertEqual(urls, [fileURL])
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

        XCTAssertEqual(collector.finish(), [fileURL])
    }
}
