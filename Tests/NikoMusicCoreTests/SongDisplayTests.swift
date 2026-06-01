import XCTest
@testable import NikoMusicCore

final class SongDisplayTests: XCTestCase {
    func testDisplayScanWarningsRedactsEmbeddedHomePaths() {
        let home = "/Users/tester"
        let song = Song(
            folderPath: URL(fileURLWithPath: "\(home)/Music/Broken"),
            originalFolderName: "Broken",
            displayTitle: "Broken",
            scanWarnings: ["Missing mixdown under \(home)/Music/Broken"]
        )

        XCTAssertEqual(
            song.displayScanWarnings(homeDirectory: home),
            ["Missing mixdown under ~/Music/Broken"]
        )
    }

    func testDisplayDryRunPathRedactsHomePrefix() {
        let home = "/Users/tester"
        let path = "\(home)/Music/Cubase/Neon Hook/Neon Hook.cpr"

        XCTAssertEqual(
            Song.displayDryRunPath(path, homeDirectory: home),
            "~/Music/Cubase/Neon Hook/Neon Hook.cpr"
        )
        XCTAssertFalse(Song.displayDryRunPath(path, homeDirectory: home).contains(home))
    }

    func testRedactPathsInTextRedactsDryRunLogLine() {
        let home = "/Users/tester"
        let raw = "[dry-run] open CPR: \(home)/Music/Neon Hook/Neon Hook.cpr"

        XCTAssertEqual(
            DiagnosticsPathRedactor.redactPathsInText(raw, homeDirectory: home),
            "[dry-run] open CPR: ~/Music/Neon Hook/Neon Hook.cpr"
        )
    }

    func testDisplaySidecarNotesReturnsNilWhenAbsent() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon"),
            originalFolderName: "Neon",
            displayTitle: "Neon Hook"
        )
        XCTAssertNil(song.displaySidecarNotes())
    }

    func testDisplaySidecarNotesRedactsEmbeddedHomePaths() {
        let home = "/Users/tester"
        let song = Song(
            folderPath: URL(fileURLWithPath: "\(home)/Music/Broken"),
            originalFolderName: "Broken",
            displayTitle: "Broken",
            sidecarNotes: "Session notes under \(home)/Music/Broken"
        )

        XCTAssertEqual(
            song.displaySidecarNotes(homeDirectory: home),
            "Session notes under ~/Music/Broken"
        )
    }
}
