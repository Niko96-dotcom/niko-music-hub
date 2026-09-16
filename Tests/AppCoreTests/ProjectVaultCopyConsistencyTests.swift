import AppCore
import NikoMusicCore
import XCTest

/// NMH-091: Get Local & Open is the only name for this action.
///
/// Guards that no user-facing `Restore & Open` copy remains on the
/// Archive Now / Get Local surfaces. Enum case names (`restoreAndOpen`)
/// and comments are intentionally allowed.
final class ProjectVaultCopyConsistencyTests: XCTestCase {
    func testUserFacingRestoreAndOpenIsGone() throws {
        let presentation = try SourceTestSupport.read(
            "Sources/AppCore/ProjectVault/ProjectVaultPresentation.swift"
        )
        let sheet = try SourceTestSupport.read(
            "Sources/FeatureArchiveBrowser/ProjectVaultRestoreSheet.swift"
        )
        XCTAssertFalse(
            presentation.contains("Restore & Open"),
            "NMH-091: no user-facing Restore & Open may remain in ProjectVaultPresentation.swift"
        )
        XCTAssertFalse(
            presentation.contains("Restore and Open"),
            "NMH-091: no user-facing Restore and Open may remain in ProjectVaultPresentation.swift"
        )
        XCTAssertFalse(
            sheet.contains("Restore & Open"),
            "NMH-091: no user-facing Restore & Open may remain in ProjectVaultRestoreSheet.swift"
        )
        XCTAssertFalse(
            sheet.contains("Restore and Open"),
            "NMH-091: no user-facing Restore and Open may remain in ProjectVaultRestoreSheet.swift"
        )
    }

    func testManagedArchiveExplanationUsesGetLocalAndOpen() {
        let record = ProjectRecord(
            canonicalTitle: "Fixture",
            locations: [
                ProjectLocation(
                    rootID: UUID(),
                    relativePath: "Fixture",
                    kind: .archive,
                    availability: .local
                )
            ]
        )
        let presentation = ProjectVaultCardPresentation(record: record)
        XCTAssertEqual(presentation.primaryAction, .restoreAndOpen)
        XCTAssertEqual(presentation.primaryAction.label, "Get Local & Open")
        XCTAssertEqual(
            presentation.explanation,
            "Get Local & Open copies this song into Active Projects, verifies the copy, then opens its newest project in the matching DAW. The archive stays intact."
        )
    }

    func testRestoreSheetBodyAvoidsRestoreVerbDisagreement() throws {
        let sheet = try SourceTestSupport.read(
            "Sources/FeatureArchiveBrowser/ProjectVaultRestoreSheet.swift"
        )
        XCTAssertTrue(
            sheet.contains("Copies the complete project into Active Projects, then opens the version you choose."),
            "NMH-091: restore sheet body must use the agreed Get Local wording"
        )
        XCTAssertTrue(
            sheet.contains("Get Local & Open"),
            "NMH-091: restore sheet primary action must stay Get Local & Open"
        )
    }
}
