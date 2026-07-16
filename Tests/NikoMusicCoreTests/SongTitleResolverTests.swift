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

    func testDisplayTitlePrefersMeaningfulFolderOverMainPreview() {
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
            "90s Rave"
        )
    }

    func testDisplayTitlePrefersMeaningfulRenamedFolderOverOlderPreviewAndCPRNames() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/GARDEN OF EDEN SESHY BOUNCE.wav"),
            fileName: "GARDEN OF EDEN SESHY BOUNCE.wav",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .mainMix,
            confidenceScore: 80
        )
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/Winter Last Day Sm Camp.cpr"),
                fileName: "Winter Last Day Sm Camp.cpr",
                modifiedAt: .distantPast
            ),
        ]

        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: "Garden Of Eden New Title",
                mainPreview: preview,
                projectVersions: versions
            ),
            "Garden Of Eden New Title"
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
                filePath: URL(fileURLWithPath: "/tmp/x/GLÜHWURM - 90s HEART V4 (feat).cpr"),
                fileName: "GLÜHWURM - 90s HEART V4 (feat).cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: 4
            ),
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/GLÜHWURM.cpr"),
                fileName: "GLÜHWURM.cpr",
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
            "90s Heart"
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
            resolver.titleFromCPRFileName("GLÜHWURM - 90s HEART V4 (Glühwurm, Writer).cpr"),
            "90s Heart"
        )
    }

    func testStemOnlyTitlesAreNeverUsedAsSongName() {
        XCTAssertTrue(resolver.isLikelyStemExportTitle("Shaker"))
        XCTAssertTrue(resolver.isLikelyStemExportTitle("Vers"))
        XCTAssertTrue(resolver.isLikelyStemExportTitle("double"))
        XCTAssertFalse(resolver.isLikelyStemExportTitle("Neon Hook"))
        XCTAssertFalse(resolver.isLikelyStemExportTitle("Turn Up The Bass"))
        XCTAssertFalse(resolver.isLikelyStemExportTitle("TURN UP THE BASS"))
    }

    func testDisplayTitleKeepsRealSongTitleWithStemWord() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/TURN UP THE BASS master.wav"),
            fileName: "TURN UP THE BASS master.wav",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .master,
            confidenceScore: 80
        )
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/TURN UP THE BASS.cpr"),
                fileName: "TURN UP THE BASS.cpr",
                modifiedAt: .distantPast
            ),
        ]

        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: "TURN UP THE BASS",
                mainPreview: preview,
                projectVersions: versions
            ),
            "Turn Up The Bass"
        )
    }

    func testDisplayTitleKeepsSongTitleWhenStemPreviewCompetes() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/bass.wav"),
            fileName: "bass.wav",
            folderRole: .stems,
            modifiedAt: .distantPast,
            detectedRole: .stems,
            confidenceScore: 80
        )
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/TURN UP THE BASS.cpr"),
                fileName: "TURN UP THE BASS.cpr",
                modifiedAt: .distantPast
            ),
        ]

        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: "TURN UP THE BASS",
                mainPreview: preview,
                projectVersions: versions
            ),
            "Turn Up The Bass"
        )
    }

    func testDisplayTitlePrefersMeaningfulFolderWhenStemPreviewCompetes() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/shaker.wav"),
            fileName: "shaker.wav",
            folderRole: .stems,
            modifiedAt: .distantPast,
            detectedRole: .stems,
            confidenceScore: 80
        )
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/Garden Of Eden.cpr"),
                fileName: "Garden Of Eden.cpr",
                modifiedAt: .distantPast
            ),
        ]

        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: "Session Exports",
                mainPreview: preview,
                projectVersions: versions
            ),
            "Session Exports"
        )
    }

    func testDisplayTitleRejectsStemPreviewAndUsesFolderWhenNoCPR() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/Vers.wav"),
            fileName: "Vers.wav",
            folderRole: .stems,
            modifiedAt: .distantPast,
            detectedRole: .unknown,
            confidenceScore: 80
        )

        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: "Midnight Drive",
                mainPreview: preview,
                projectVersions: []
            ),
            "Midnight Drive"
        )
    }

    func testDisplayTitlePrefersMeaningfulFolderOverNonBounceStemAndCPR() {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/x/double.wav"),
            fileName: "double.wav",
            folderRole: .root,
            modifiedAt: .distantPast,
            detectedRole: .unknown,
            confidenceScore: 80
        )
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/x/Neon Hook.cpr"),
                fileName: "Neon Hook.cpr",
                modifiedAt: .distantPast
            ),
        ]

        XCTAssertEqual(
            resolver.displayTitle(
                fromFolderName: "Wrong Folder Label",
                mainPreview: preview,
                projectVersions: versions
            ),
            "Wrong Folder Label"
        )
    }
}
