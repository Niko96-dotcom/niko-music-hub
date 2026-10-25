import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// The library owner on its own: the root-change rule, the scan error rule, what a stored-settings
/// change means, and the write guard.
@MainActor
final class ArchiveLibraryModelTests: XCTestCase {
    private struct NoDiagnostics: Diagnostics {
        func log(_ level: DiagnosticLevel, _ message: String) {}
    }

    private struct UnreadableSettingsStore: SettingsStore {
        struct Failure: Error {}
        func loadSettings() throws -> AppSettings { throw Failure() }
        func saveSettings(_ settings: AppSettings) throws { throw Failure() }
        func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws { throw Failure() }
    }

    /// What the library reported.
    private final class Reports {
        var rootChanges = 0
        var scanningChanges = 0
        var warnings: [ArchiveFooterStatus.Warning] = []
    }

    private func makeStore() throws -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: "ArchiveLibraryModelTests.\(UUID())")),
            key: "settings"
        )
    }

    private func makeLibrary(_ store: SettingsStore, reports: Reports = Reports()) -> ArchiveLibraryModel {
        ArchiveLibraryModel(
            settingsStore: store,
            appSettings: AppSettingsObserver(store: store),
            diagnostics: NoDiagnostics(),
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.settingsSuiteKey: "ArchiveLibraryModelTests",
            ]),
            bookmarkProvider: FoundationSecurityScopedBookmarks(),
            host: ArchiveLibraryHost(
                raiseWarning: { reports.warnings.append($0) },
                resolveWarning: { _ in },
                rootsDidChange: { reports.rootChanges += 1 },
                scanningDidChange: { reports.scanningChanges += 1 }
            )
        )
    }

    func testARootChangeBumpsTheGenerationAndEndsTheScan() throws {
        let reports = Reports()
        let library = makeLibrary(try makeStore(), reports: reports)
        library.isScanning = true
        let generation = library.rootGeneration

        library.roots = [URL(fileURLWithPath: "/tmp/library/A", isDirectory: true)]

        XCTAssertEqual(library.rootGeneration, generation &+ 1)
        XCTAssertFalse(library.isScanning)
        XCTAssertEqual(reports.rootChanges, 1)

        library.roots = [URL(fileURLWithPath: "/tmp/library/A/", isDirectory: true)]
        XCTAssertEqual(library.rootGeneration, generation &+ 1, "the same folder spelled again is no change")
        XCTAssertEqual(reports.rootChanges, 1)
    }

    func testANewScanDismissesTheScanError() throws {
        let reports = Reports()
        let library = makeLibrary(try makeStore(), reports: reports)
        library.recordScanFailure()
        XCTAssertNotNil(library.scanError)
        XCTAssertNil(library.scanDiagnostics)

        library.isScanning = true

        XCTAssertNil(library.scanError)
        XCTAssertEqual(reports.scanningChanges, 1, "the jobs strip follows")
    }

    func testAStoredSettingsChangeSaysWhatItMeans() throws {
        let store = try makeStore()
        let folder = URL(fileURLWithPath: "/tmp/library/Scan", isDirectory: true)
        try store.updateSettings { $0.musicRoots = [StoredMusicRoot(role: .scanOnly, url: folder)] }
        let library = makeLibrary(store)
        library.loadRootsFromSettings()

        XCTAssertEqual(library.noteStoredSettings(), .none, "what it already follows")

        try store.updateSettings { $0.vault.keepLocalReviewRequired.toggle() }
        XCTAssertEqual(library.noteStoredSettings(), .vaultChoices)

        try store.updateSettings { $0.musicRoots = [] }
        XCTAssertEqual(library.noteStoredSettings(), .roots(vaultBindingChanged: false))

        try store.updateSettings { $0.vault.isEnabled.toggle() }
        XCTAssertEqual(library.noteStoredSettings(), .roots(vaultBindingChanged: true))
    }

    func testUnreadableSettingsRefuseAWriteAndChangeNothingFollowed() {
        let library = makeLibrary(UnreadableSettingsStore())

        XCTAssertThrowsError(try library.loadSettingsForWrite()) { error in
            XCTAssertEqual(error as? ArchiveWriteGuardError, .settingsUnreadable)
        }
        XCTAssertThrowsError(try library.writeProtectedRoots())
        XCTAssertEqual(library.noteStoredSettings(), .none)
    }

    func testTheVaultArchiveRootStaysWriteProtectedWhileVaultIsOff() throws {
        let store = try makeStore()
        let archive = StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/library/Vault", isDirectory: true))
        try store.updateSettings { settings in
            settings.musicRoots = [archive]
            settings.vault.isEnabled = false
            settings.vault.archiveRootID = archive.id
        }
        let library = makeLibrary(store)
        library.roots = [URL(fileURLWithPath: "/tmp/library/Scan", isDirectory: true)]

        let protected = try library.writeProtectedRoots().map(\.path)

        XCTAssertEqual(protected, ["/tmp/library/Scan", archive.fallbackURL.path])
    }
}
