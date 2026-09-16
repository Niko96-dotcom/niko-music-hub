import Foundation
import NikoMusicCore
import XCTest
@testable import AppCore

/// NMH-055: Settings vault diagnostics export uses a dated default name (no silent
/// overwrite of a fixed name) while the archive-root write guard stays fail-closed.
/// Fixture-free: all destinations live under the temporary directory.
final class ProjectVaultDiagnosticsExporterUniqueNameTests: XCTestCase {
    func testWriteGuardStillRefusesArchiveRoot() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-055-guard-\(UUID().uuidString)", isDirectory: true)
        let archiveRoot = base.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        var settings = AppSettings()
        settings.musicRoots = [StoredMusicRoot(role: .archive, url: archiveRoot)]
        let health = ProjectVaultHealth(
            providerStatus: .availableLocal,
            lastSuccessfulVerificationAt: nil,
            hasIndependentBackup: false
        )
        let destination = archiveRoot
            .appendingPathComponent("project-vault-diagnostics-2026-09-15.txt")

        XCTAssertThrowsError(
            try ProjectVaultDiagnosticsExporter.export(
                settings: settings,
                health: health,
                to: destination
            )
        ) { error in
            XCTAssertEqual(error as? ProjectVaultDiagnosticsExportError, .destinationInsideMusicRoot)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.path),
            "A refused export must not leave a file behind."
        )
    }

    func testDefaultFilenameUsesDateNotFixedName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)
        )!
        XCTAssertEqual(
            ProjectVaultDiagnosticsExportCopy.filename(
                for: date,
                calendar: calendar,
                timeZone: calendar.timeZone
            ),
            "project-vault-diagnostics-2026-09-15.txt"
        )
    }

    func testReplaceCopyNamesFileAndStatesNoUndo() {
        XCTAssertEqual(ProjectVaultDiagnosticsExportCopy.replaceTitle, "Replace this file?")
        let message = ProjectVaultDiagnosticsExportCopy.replaceMessage(
            filename: "project-vault-diagnostics-2026-09-15.txt"
        )
        XCTAssertEqual(
            message,
            "A file named “project-vault-diagnostics-2026-09-15.txt” already exists in this folder. Replacing it cannot be undone from Niko Music Hub."
        )
    }
}
