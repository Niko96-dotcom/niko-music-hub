import XCTest
@testable import NikoMusicCore

final class DiagnosticsPathRedactorTests: XCTestCase {
    func testRedactsHomePrefix() {
        let home = "/Users/tester"
        let input = "\(home)/Music/Cubase/Neon Hook/Neon Hook.cpr"
        XCTAssertEqual(
            DiagnosticsPathRedactor.redact(input, homeDirectory: home),
            "~/Music/Cubase/Neon Hook/Neon Hook.cpr"
        )
    }

    func testLeavesPathsOutsideHomeUntouched() {
        let home = "/Users/tester"
        let input = "/Volumes/Archive/Neon Hook.cpr"
        XCTAssertEqual(
            DiagnosticsPathRedactor.redact(input, homeDirectory: home),
            input
        )
    }

    func testRedactPathsInTextReplacesEmbeddedHomePaths() {
        let home = "/Users/tester"
        let input = "No CPR at \(home)/Music/Cubase/Broken/Broken.cpr — check folder"
        XCTAssertEqual(
            DiagnosticsPathRedactor.redactPathsInText(input, homeDirectory: home),
            "No CPR at ~/Music/Cubase/Broken/Broken.cpr — check folder"
        )
    }

    func testLeavesSiblingHomeDirectoryUntouched() {
        // "/Users/testerson" shares the prefix of "/Users/tester" but is another account.
        let home = "/Users/tester"
        let sibling = "/Users/testerson/Music/Other.cpr"
        XCTAssertEqual(DiagnosticsPathRedactor.redact(sibling, homeDirectory: home), sibling)
        XCTAssertEqual(DiagnosticsPathRedactor.redact(home, homeDirectory: home), "~")
    }

    func testRedactPathsInTextLeavesSiblingHomeDirectoryUntouched() {
        let home = "/Users/tester"
        let input = "Copied /Users/testerson/Music/Other.cpr next to \(home)/Music/Mine.cpr"
        XCTAssertEqual(
            DiagnosticsPathRedactor.redactPathsInText(input, homeDirectory: home),
            "Copied /Users/testerson/Music/Other.cpr next to ~/Music/Mine.cpr"
        )
    }

    func testRedactPathsInTextLeavesNonHomePathsUntouched() {
        let home = "/Users/tester"
        let input = "External archive at /Volumes/Studio/Song.cpr"
        XCTAssertEqual(
            DiagnosticsPathRedactor.redactPathsInText(input, homeDirectory: home),
            input
        )
    }
}
