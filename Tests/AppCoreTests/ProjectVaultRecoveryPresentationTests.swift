import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class ProjectVaultRecoveryPresentationTests: XCTestCase {
    func testAvailabilityIsSeparateFromArchivedState() {
        for (availability, label) in [(Availability.local, "Archived · Local"), (.onlineOnly, "Archived · Online-only"), (.materializing, "Archived · Downloading")] {
            let record = ProjectRecord(canonicalTitle: "Fixture", locations: [
                ProjectLocation(rootID: UUID(), relativePath: "Fixture", kind: .archive, availability: availability)
            ])
            let presentation = ProjectVaultCardPresentation(record: record, linkedArchiveAvailability: availability)
            XCTAssertEqual(presentation.statusLabel, label)
            XCTAssertEqual(presentation.primaryAction, .restoreAndOpen)
        }
        let missing = ProjectRecord(canonicalTitle: "Fixture", locations: [
            ProjectLocation(rootID: UUID(), relativePath: "Fixture", kind: .archive, availability: .missing)
        ])
        let presentation = ProjectVaultCardPresentation(record: missing)
        XCTAssertEqual(presentation.statusLabel, "Needs attention · Unavailable")
        XCTAssertEqual(presentation.primaryAction, .review)
    }

    func testEveryRecoverableRestoreFailureHasAnActionAndStageSpecificExplanation() {
        let record = ProjectRecord(canonicalTitle: "Fixture", locations: [])
        var explanations = Set<String>()
        for phase in VaultRestorePhase.allCases where phase != .superseded {
            var restore = makeRestore(projectID: record.id, phase: phase)
            restore.error = "fixture failure"
            let presentation = ProjectVaultCardPresentation(record: record, restore: restore)
            XCTAssertEqual(presentation.state, .needsAttention)
            XCTAssertEqual(presentation.retryRestoreID, restore.id)
            XCTAssertEqual(presentation.primaryActionLabel, phase == .openingInCubase ? "Retry Open" : "Retry Restore")
            explanations.insert(presentation.explanation)
            restore.failureReason = .activeDestinationIntegrityMismatch
            let unsafe = ProjectVaultCardPresentation(record: record, restore: restore)
            XCTAssertNil(unsafe.retryRestoreID)
            XCTAssertEqual(unsafe.primaryAction, .review)
        }
        XCTAssertEqual(explanations.count, 6)
    }

    func testProgressReportsStageAndTotalScopeWithoutCompletionPercentage() {
        let entry = VaultManifest.Entry(relativePath: "Fixture.cpr", type: .regularFile,
            byteCount: 1024, modifiedAt: Date(), sha256: nil)
        let progress = ProjectVaultRestoreProgress(phase: .verifyingActiveStaging,
            manifest: VaultManifest(entries: [entry]))
        XCTAssertEqual(progress.title, "Verifying restored files")
        XCTAssertEqual(progress.fileCount, 1)
        XCTAssertEqual(progress.totalBytes, 1024)
        XCTAssertTrue(progress.scopeDescription?.hasSuffix("total") == true)
        XCTAssertNil(ProjectVaultRestoreProgress(phase: .materializingArchive).scopeDescription)
    }

    private func makeRestore(projectID: ProjectID, phase: VaultRestorePhase) -> VaultRestoreRecord {
        let root = URL(fileURLWithPath: "/tmp/disposable-recovery-presentation")
        return VaultRestoreRecord(projectID: projectID, archiveGenerationURL: root.appendingPathComponent("archive"),
            stagingURL: root.appendingPathComponent("staging"), destinationURL: root.appendingPathComponent("active"),
            manifest: VaultManifest(entries: []), phase: phase)
    }
}
