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
}
