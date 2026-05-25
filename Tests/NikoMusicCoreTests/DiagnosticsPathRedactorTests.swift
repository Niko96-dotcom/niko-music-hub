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
}
