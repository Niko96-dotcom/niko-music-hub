import AppCore
import NikoMusicCore
import XCTest

/// NMH-054: restore progress is determinate when totals exist.
final class ProjectVaultRestoreProgressTests: XCTestCase {
    func testFractionClamped() {
        let half = ProjectVaultRestoreProgress(
            phase: .copyingToActiveStaging, totalBytes: 100, fileCount: 2, copiedBytes: 50)
        XCTAssertEqual(half.fraction, 0.5)

        let over = ProjectVaultRestoreProgress(
            phase: .verifyingActiveStaging, totalBytes: 100, fileCount: 2, copiedBytes: 250)
        XCTAssertEqual(over.fraction, 1)

        let zeroTotal = ProjectVaultRestoreProgress(
            phase: .materializingArchive, totalBytes: 0, fileCount: 0, copiedBytes: 0)
        XCTAssertNil(zeroTotal.fraction)

        let unknownTotals = ProjectVaultRestoreProgress(phase: .materializingArchive)
        XCTAssertNil(unknownTotals.totalBytes)
        XCTAssertNil(unknownTotals.fraction)
    }

    func testManifestTotalsStayHonest() {
        let entry = VaultManifest.Entry(
            relativePath: "Fixture.cpr", type: .regularFile,
            byteCount: 100, modifiedAt: Date(), sha256: nil)
        let progress = ProjectVaultRestoreProgress(
            phase: .copyingToActiveStaging,
            manifest: VaultManifest(entries: [entry]),
            copiedBytes: 50)
        XCTAssertEqual(progress.totalBytes, 100)
        XCTAssertEqual(progress.fileCount, 1)
        XCTAssertEqual(progress.fraction, 0.5)
        XCTAssertTrue(progress.scopeDescription?.hasSuffix("total") == true)
    }

    func testChecklistCoversEveryPhaseExceptSuperseded() {
        let phases = ProjectVaultRestoreProgress.checklistPhases
        XCTAssertFalse(phases.contains(.superseded))
        XCTAssertEqual(phases.count, VaultRestorePhase.allCases.count - 1)
        XCTAssertEqual(
            ProjectVaultRestoreProgress(phase: .verifyingActiveStaging).checklistIndex, 2)
        XCTAssertNil(ProjectVaultRestoreProgress(phase: .superseded).checklistIndex)
    }

    func testVaultTransferStatusCarriesFraction() {
        let progress = ProjectVaultRestoreProgress(
            phase: .copyingToActiveStaging, totalBytes: 100, fileCount: 1, copiedBytes: 42)
        let status = ShellJobStatusCopy.vaultTransferStatus(songName: "Fixture", progress: progress)
        XCTAssertEqual(status.percent, 0.42)
        XCTAssertTrue(status.displayLine.contains("42%"))
    }
}
