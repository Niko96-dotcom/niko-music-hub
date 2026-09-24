import AppCore
import NikoMusicCore
import XCTest

/// NMH-091: one name for this action, everywhere. The name is Restore & Open
/// (it was Get Local & Open until the 2026-09-24 copy pass; the rule is the
/// single name, not the specific words).
///
/// Guards that no `Get Local` copy survives anywhere under `Sources/`.
/// Enum case names (`restoreAndOpen`) are intentionally unaffected.
final class ProjectVaultCopyConsistencyTests: XCTestCase {
    func testRetiredGetLocalNameIsGone() throws {
        let sources = SourceTestSupport.packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("Get Local") {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(offenders, [], "NMH-091: the retired name Get Local must not appear in Sources/")
    }

    func testManagedArchiveExplanationUsesRestoreAndOpen() {
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
        XCTAssertEqual(presentation.primaryAction.label, "Restore & Open")
        XCTAssertEqual(
            presentation.explanation,
            "Restore & Open copies this song back to Active Projects, verifies it, and opens the newest version. The Vault copy stays as it is."
        )
    }

    func testRestoreSheetBodyAvoidsRestoreVerbDisagreement() throws {
        let sheet = try SourceTestSupport.read(
            "Sources/FeatureArchiveBrowser/ProjectVaultRestoreSheet.swift"
        )
        XCTAssertTrue(
            sheet.contains("Copies the complete project into Active Projects, then opens the version you choose."),
            "NMH-091: restore sheet body must use the agreed Restore & Open wording"
        )
        XCTAssertTrue(
            sheet.contains("Restore & Open"),
            "NMH-091: restore sheet primary action must stay Restore & Open"
        )
    }
}
