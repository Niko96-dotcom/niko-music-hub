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
            detectedRole: .master,
            confidenceScore: 80
        )
        XCTAssertEqual(
            resolver.displayTitle(fromFolderName: "90s Rave", mainPreview: preview),
            "Graffiti"
        )
    }

    func testDisplayTitlePrefersCPROverWeakFolderAndDemoPreview() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/demo v0.6.mp3"),
            fileName: "demo v0.6.mp3",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .preview,
            confidenceScore: 40
        )
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/BLÜMCHEN - 90s ICON V4 (feat).cpr"),
                fileName: "BLÜMCHEN - 90s ICON V4 (feat).cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: 4
            ),
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/BLÜMCHEN.cpr"),
                fileName: "BLÜMCHEN.cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: nil
            ),
        ]
        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: ".6",
                mainPreview: preview,
                projectVersions: versions
            ),
            "90s Icon"
        )
    }

    func testDisplayTitleFallsBackToFolderWhenPreviewIsUUID() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/15923c89-209a-814d-e409-d7e3d294.wav"),
            fileName: "15923c89-209a-814d-e409-d7e3d294.wav",
            folderRole: .root,
            modifiedAt: .distantPast,
            detectedRole: .unknown,
            confidenceScore: 10
        )
        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: "Topline Day Three",
                mainPreview: preview,
                projectVersions: []
            ),
            "Topline Day Three"
        )
    }

    func testTitleFromCPRStripsArtistAndVersion() {
        XCTAssertEqual(
            resolver.titleFromCPRFileName("BLÜMCHEN - 90s ICON V4 (Blümchen, Niko Mohr).cpr"),
            "90s Icon"
        )
    }
}
