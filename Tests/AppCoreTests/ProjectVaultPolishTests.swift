import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class ProjectVaultPolishTests: XCTestCase {
    func testRestoreDrillUsesOnlyItsSyntheticTemporaryFixtureAndPreservesArchive() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let date = Date(timeIntervalSince1970: 123)

        let result = try ProjectVaultRestoreDrill(temporaryDirectory: parent, now: { date }).run()

        XCTAssertEqual(result.completedAt, date)
        XCTAssertEqual(result.fileCount, 2)
        XCTAssertTrue(result.archiveCopyPreserved)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: parent.path)).isEmpty)
    }

    func testDiagnosticsOmitsPathsAndRefusesMusicRootDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let music = root.appendingPathComponent("Secret Artist Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stored = StoredMusicRoot(role: .archive, url: music)
        var settings = AppSettings(musicRoots: [stored])
        settings.vault.archiveRootID = stored.id
        let health = ProjectVaultHealth(providerStatus: .availableLocal, lastSuccessfulVerificationAt: nil, hasIndependentBackup: false)

        let text = ProjectVaultDiagnosticsExporter.formattedText(settings: settings, health: health)
        XCTAssertFalse(text.contains(music.path))
        XCTAssertTrue(text.contains("provider_status=availableLocal"))
        XCTAssertThrowsError(try ProjectVaultDiagnosticsExporter.export(settings: settings, health: health, to: music.appendingPathComponent("diag.txt"))) {
            XCTAssertEqual($0 as? ProjectVaultDiagnosticsExportError, .destinationInsideMusicRoot)
        }
    }

    func testRolloutPolicyFailsClosedUntilFriendsStageAndBothRoots() {
        var settings = VaultSettings(isEnabled: true, activeRootID: UUID(), archiveRootID: UUID())
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
        settings.rolloutStage = .friends
        XCTAssertTrue(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
        settings.automationEmergencyStop = true
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(settings))
    }
}
