import XCTest
@testable import NikoMusicCore

final class PreviewRankingProjectContextTests: XCTestCase {
    func testBuildsAnchorAndTitleTokensFromCPRs() {
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/GLÜHWURM - 90s HEART V4.cpr"),
                fileName: "GLÜHWURM - 90s HEART V4 (Glühwurm, Writer).cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: 4
            ),
        ]
        let context = PreviewRankingProjectContext.from(projectVersions: versions)
        XCTAssertEqual(context.anchorCPRVersion, 4)
        XCTAssertTrue(context.titleTokens.contains("90s"))
        XCTAssertTrue(context.titleTokens.contains("heart"))
    }

    func testAnchorRetainsExplicitV3OverDateSuffix() {
        let detected = CPRVersionDetector.parseVersionNumber(from: "Song v3 2024.cpr")
        XCTAssertEqual(detected, 3)
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/Song v3 2024.cpr"),
                fileName: "Song v3 2024.cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: detected
            ),
        ]
        XCTAssertEqual(PreviewRankingProjectContext.from(projectVersions: versions).anchorCPRVersion, 3)
    }

    func testAnchorNilForPlainYearAndValueForSmallBare() {
        let plainYear = CPRVersionDetector.parseVersionNumber(from: "Song 2024.cpr")
        XCTAssertNil(plainYear)
        let plainVersions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/Song 2024.cpr"),
                fileName: "Song 2024.cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: plainYear
            ),
        ]
        XCTAssertNil(PreviewRankingProjectContext.from(projectVersions: plainVersions).anchorCPRVersion)

        let bare = CPRVersionDetector.parseVersionNumber(from: "Song 3.cpr")
        XCTAssertEqual(bare, 3)
        let bareVersions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/Song 3.cpr"),
                fileName: "Song 3.cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: bare
            ),
        ]
        XCTAssertEqual(PreviewRankingProjectContext.from(projectVersions: bareVersions).anchorCPRVersion, 3)
    }
}
