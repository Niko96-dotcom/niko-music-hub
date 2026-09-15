import Foundation
import XCTest
@testable import NikoMusicCore

final class LinkedArchiveInventoryTests: XCTestCase {
    func testDownloadInventoryDetectsAddedAndChangedFilesWithoutHashing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Song.cpr")
        try Data("original".utf8).write(to: file)
        let inventory = LinkedArchiveInventory()
        let before = try inventory.materializationManifest(at: root)
        XCTAssertNil(before.entries.first?.sha256)
        try inventory.verifyMetadata(before, against: inventory.materializationManifest(at: root))
        try Data("longer changed content".utf8).write(to: file)
        XCTAssertThrowsError(try inventory.verifyMetadata(before, against: inventory.materializationManifest(at: root)))
        let changed = try inventory.materializationManifest(at: root)
        try Data("new".utf8).write(to: root.appendingPathComponent("New.wav"))
        XCTAssertThrowsError(try inventory.verifyMetadata(changed, against: inventory.materializationManifest(at: root)))
    }

    func testDownloadInventoryRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"),
            withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try LinkedArchiveInventory().materializationManifest(at: root))
    }
}
