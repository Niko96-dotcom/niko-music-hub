import XCTest
@testable import NikoMusicCore

final class PreviewFilenameParserTests: XCTestCase {
    func testParsesMultiDigitVersionFromTrailingToken() {
        XCTAssertEqual(PreviewFilenameParser.parseVersionNumber(from: "Song v10 mix.wav"), 10)
        XCTAssertEqual(PreviewFilenameParser.parseVersionNumber(from: "Song v2 mix.wav"), 2)
    }

    func testPrefersRightmostVersionTokenOverEarlierDigits() {
        XCTAssertEqual(PreviewFilenameParser.parseVersionNumber(from: "Track v2 v5 bounce.wav"), 5)
    }

    func testParsesVersionFromUnderscoreAndDashSeparatedStems() {
        XCTAssertEqual(PreviewFilenameParser.parseVersionNumber(from: "track_v12-final.wav"), 12)
        XCTAssertEqual(PreviewFilenameParser.parseVersionNumber(from: "Lab-Song-v3-mix.wav"), 3)
    }

    func testReturnsNilWhenNoVersionToken() {
        XCTAssertNil(PreviewFilenameParser.parseVersionNumber(from: "Song mix.wav"))
        XCTAssertNil(PreviewFilenameParser.parseVersionNumber(from: "Song final bounce.wav"))
    }

    func testRejectsNonPositiveVersionNumbers() {
        XCTAssertNil(PreviewFilenameParser.parseVersionNumber(from: "Song v0.wav"))
    }
}
