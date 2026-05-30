import XCTest
@testable import NikoMusicCore

final class SongTitleResolverTests: XCTestCase {
    private let resolver = SongTitleResolver()

    func testInfersTitleFromSessionBounceFilename() {
        XCTAssertEqual(
            resolver.inferredTitle(fromPreviewFileName: "Graffiti SESSIN BOUNCE.wav"),
            "Graffiti"
        )
    }

    func testInfersTitleStripsVersionAndMixTokens() {
        XCTAssertEqual(
            resolver.inferredTitle(fromPreviewFileName: "Lab Song v3 mix.wav"),
            "Lab Song"
        )
    }

    func testDisplayTitleFallsBackToFolderWithoutPreview() {
        XCTAssertEqual(
            resolver.displayTitle(fromFolderName: "90s Rave", mainPreview: nil),
            "90s Rave"
        )
    }

    func testDisplayTitleUsesMainPreviewWhenPresent() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/Graffiti master.wav"),
            fileName: "Graffiti master.wav",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .master
        )
        XCTAssertEqual(
            resolver.displayTitle(fromFolderName: "90s Rave", mainPreview: preview),
            "Graffiti"
        )
    }
}
