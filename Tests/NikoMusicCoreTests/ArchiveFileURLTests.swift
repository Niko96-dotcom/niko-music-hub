import Foundation
@testable import NikoMusicCore
import XCTest

final class ArchiveFileURLTests: XCTestCase {
    func testPreservesURLValueAndExistingJSONFormat() throws {
        let urls = [
            URL(fileURLWithPath: "/fixture-only/Über uns/曲 1/Mixdown/a#b.wav"),
            URL(fileURLWithPath: "/fixture-only/Folder", isDirectory: true),
            try XCTUnwrap(URL(string: "file:///fixture-only/a%20b.cpr")),
            try XCTUnwrap(URL(string: "https://example.invalid/a?b=c#d")),
        ]
        for url in urls {
            let compact = ArchiveFileURL(wrappedValue: url)
            XCTAssertEqual(compact.wrappedValue, url)
            XCTAssertEqual(compact.wrappedValue.absoluteString, url.absoluteString)
            XCTAssertEqual(compact.wrappedValue.hasDirectoryPath, url.hasDirectoryPath)
            XCTAssertEqual(try JSONEncoder().encode(compact), try JSONEncoder().encode(url))
            let decoded = try JSONDecoder().decode(ArchiveFileURL.self, from: JSONEncoder().encode(url))
            XCTAssertEqual(decoded, compact)
            XCTAssertEqual(decoded.hashValue, compact.hashValue)
        }
    }

    func testScannedAndDecodedPathsDoNotRetainEnumerationMetadata() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/archive-url-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("Song.cpr")
        try Data([0]).write(to: path)
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        let newDate = oldDate.addingTimeInterval(100)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: path.path)
        let enumerated = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ).first)
        _ = try enumerated.resourceValues(forKeys: [.contentModificationDateKey])
        let version = ProjectVersion(filePath: enumerated, fileName: "Song.cpr", modifiedAt: oldDate)
        let decoded = try JSONDecoder().decode(ProjectVersion.self, from: JSONEncoder().encode(version))
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: path.path)
        for value in [version, decoded] {
            XCTAssertEqual(value.modifiedAt, oldDate, "The scan's recorded timestamp remains its snapshot value")
            XCTAssertEqual(try value.filePath.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, newDate)
        }
    }
}
