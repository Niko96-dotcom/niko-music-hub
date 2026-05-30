import XCTest
@testable import NikoMusicCore

final class PreviewRankingProjectContextTests: XCTestCase {
    func testBuildsAnchorAndTitleTokensFromCPRs() {
        let versions = [
            ProjectVersion(
                filePath: URL(fileURLWithPath: "/tmp/BLÜMCHEN - 90s ICON V4.cpr"),
                fileName: "BLÜMCHEN - 90s ICON V4 (Blümchen, Niko Mohr).cpr",
                modifiedAt: .distantPast,
                detectedVersionNumber: 4
            ),
        ]
        let context = PreviewRankingProjectContext.from(projectVersions: versions)
        XCTAssertEqual(context.anchorCPRVersion, 4)
        XCTAssertTrue(context.titleTokens.contains("90s"))
        XCTAssertTrue(context.titleTokens.contains("icon"))
    }
}
