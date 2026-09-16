import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class ProjectVaultRestoreOptionsTests: XCTestCase {
    func testVersionChoicesExcludeFilesTheOpenerDoesNotOffer() {
        let paths = ["Main.cpr", "Versions/Older.als", "Live/Backup/Auto.als", "Ableton Project Info/Cache.als", "Main.bak.cpr", ".hidden.cpr", "Audio/take.wav"]
        let manifest = VaultManifest(entries: paths.map {
            VaultManifest.Entry(relativePath: $0, type: .regularFile, byteCount: 0,
                modifiedAt: .distantPast, sha256: nil)
        })
        let options = ProjectVaultRestoreOptions(manifest: manifest,
            activeRoot: URL(fileURLWithPath: "/tmp/Active"), destinationRelativePath: "Restored")
        XCTAssertEqual(options.versions.map(\.relativePath), ["Main.cpr", "Versions/Older.als"])
        XCTAssertNotNil(options.destinationIssue(for: "../Outside"))
        XCTAssertNotNil(options.destinationIssue(for: "/Outside"))
        XCTAssertNotNil(options.destinationIssue(for: ".niko-staging/Project"))
    }

    func testSuggestedUniqueNameWhenOccupied() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Hook"),
            withIntermediateDirectories: true)
        let manifest = VaultManifest(entries: [])
        let options = ProjectVaultRestoreOptions(manifest: manifest, activeRoot: root,
            destinationRelativePath: "Hook")
        XCTAssertNotNil(options.destinationIssue(for: "Hook"))
        XCTAssertEqual(options.suggestedUniqueRelativePath(for: "Hook"), "Hook 2")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Hook 2"),
            withIntermediateDirectories: true)
        XCTAssertEqual(options.suggestedUniqueRelativePath(for: "Hook"), "Hook 3")
    }
}
