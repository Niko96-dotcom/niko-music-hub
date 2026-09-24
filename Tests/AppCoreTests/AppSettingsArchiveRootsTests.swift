import AppCore
import Foundation
import XCTest

final class AppSettingsArchiveRootsTests: XCTestCase {
    func testArchiveRootsSetterToleratesDuplicateScanOnlyRoots() {
        let path = "/Volumes/Music/Archive"
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(role: .scanOnly, url: URL(fileURLWithPath: path, isDirectory: true)),
            StoredMusicRoot(role: .scanOnly, url: URL(fileURLWithPath: path, isDirectory: true)),
            StoredMusicRoot(role: .active, url: URL(fileURLWithPath: "/Volumes/Music/Active", isDirectory: true)),
        ]

        // Previously trapped in Dictionary(uniqueKeysWithValues:) on the duplicate path.
        settings.archiveRoots = [StoredArchiveRoot(path: path)]

        let scanRoots = settings.musicRoots.filter { $0.role == .scanOnly }
        XCTAssertEqual(scanRoots.count, 1)
        XCTAssertEqual(settings.musicRoots.filter { $0.role == .active }.count, 1, "Vault roots are retained")
        XCTAssertEqual(settings.archiveRoots.map(\.path), [path])
    }

    func testArchiveRootsSetterKeepsExistingBookmarkForSamePath() {
        let path = "/Volumes/Music/Archive"
        let bookmark = Data("bookmark".utf8)
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(
                role: .scanOnly,
                url: URL(fileURLWithPath: path, isDirectory: true),
                securityScopedBookmark: bookmark
            ),
        ]

        settings.archiveRoots = [StoredArchiveRoot(path: path)]

        XCTAssertEqual(settings.musicRoots.first?.securityScopedBookmark, bookmark)
    }
}
