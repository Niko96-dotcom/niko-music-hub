import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class VaultSettingsTests: XCTestCase {
    func testVaultDefaultsAreOptInAndMatchPolicy() {
        let vault = AppSettings.default.vault
        XCTAssertFalse(vault.isEnabled)
        XCTAssertNil(vault.activeRootID)
        XCTAssertNil(vault.archiveRootID)
        XCTAssertTrue(vault.automaticArchiving)
        XCTAssertEqual(vault.inactivityDays, 30)
        XCTAssertEqual(vault.minimumFreeSpaceGiB, 120)
        XCTAssertEqual(vault.transferFreeSpaceReserveGiB, 5)
        XCTAssertEqual(vault.keepPreviousGenerationDays, 30)
        XCTAssertTrue(vault.launchAtLogin)
    }

    func testLegacyPressureThresholdDecodesIndependentlyOfTransferReserve() throws {
        let legacy = Data(#"{"isEnabled":true,"minimumFreeSpaceGiB":120}"#.utf8)
        var settings = try JSONDecoder().decode(VaultSettings.self, from: legacy)
        XCTAssertEqual(settings.minimumFreeSpaceGiB, 120)
        XCTAssertEqual(settings.transferFreeSpaceReserveGiB, 5)
        settings.transferFreeSpaceReserveGiB = 12
        let restored = try JSONDecoder().decode(VaultSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.minimumFreeSpaceGiB, 120)
        XCTAssertEqual(restored.transferFreeSpaceReserveGiB, 12)
    }

    func testLegacyRootsMigrateToScanOnlyAndPersistTypedIdentity() throws {
        let defaults = try makeDefaults()
        let legacy = #"{"archiveRoots":[{"path":"/tmp/legacy-one"},{"path":"/tmp/legacy-two"}]}"#
        defaults.set(Data(legacy.utf8), forKey: "nikoMusicHub.settings")
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded.musicRoots.map(\.role), [.scanOnly, .scanOnly])
        XCTAssertEqual(loaded.musicRoots.map(\.pathFallback), ["/tmp/legacy-one", "/tmp/legacy-two"])
        let firstIDs = loaded.musicRoots.map(\.id)
        XCTAssertEqual(try store.loadSettings().musicRoots.map(\.id), firstIDs)
        let persisted = try XCTUnwrap(defaults.data(forKey: "nikoMusicHub.settings"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        XCTAssertNotNil(object["musicRoots"])
        XCTAssertNil(object["archiveRoots"])
    }

    func testRoundTripPersistsBookmarksAndSelectedIDs() throws {
        let defaults = try makeDefaults()
        let active = StoredMusicRoot(role: .active, url: URL(fileURLWithPath: "/tmp/active"), securityScopedBookmark: Data([1, 2]))
        let archive = StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/archive"), securityScopedBookmark: Data([3, 4]))
        let settings = AppSettings(
            musicRoots: [active, archive],
            vault: VaultSettings(isEnabled: true, activeRootID: active.id, archiveRootID: archive.id)
        )
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        try store.saveSettings(settings)

        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded.musicRoots, [active, archive])
        XCTAssertEqual(loaded.vault.activeRootID, active.id)
        XCTAssertEqual(loaded.vault.archiveRootID, archive.id)
    }

    func testDisabledVaultPreservesLegacyEffectiveScanRootsExactly() {
        let legacy = [StoredArchiveRoot(path: "/tmp/one"), StoredArchiveRoot(path: "/tmp/two")]
        var settings = AppSettings(archiveRoots: legacy)
        settings.musicRoots.append(StoredMusicRoot(role: .active, url: URL(fileURLWithPath: "/tmp/active")))
        settings.musicRoots.append(StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/archive")))
        settings.vault.isEnabled = false

        XCTAssertEqual(settings.effectiveScanRoots.map(\.pathFallback), legacy.map(\.path))
        XCTAssertEqual(settings.archiveRoots, legacy)
    }

    func testEnabledVaultDeduplicatesScanOnlyAndSelectedActiveRootByCanonicalPath() {
        let sharedURL = URL(fileURLWithPath: "/tmp/shared-projects")
        let scanOnly = StoredMusicRoot(role: .scanOnly, url: sharedURL)
        let active = StoredMusicRoot(role: .active, url: sharedURL)
        let archive = StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/vault-archive"))
        let settings = AppSettings(
            musicRoots: [scanOnly, active, archive],
            vault: VaultSettings(
                isEnabled: true,
                activeRootID: active.id,
                archiveRootID: archive.id
            )
        )

        XCTAssertEqual(settings.effectiveScanRoots.map(\.id), [active.id, archive.id])
    }

    func testReplacingRootsChangesOnlySettingsAndDoesNotMoveContent() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let active = base.appendingPathComponent("active", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let marker = active.appendingPathComponent("Song.cpr")
        try Data("untouched".utf8).write(to: marker)
        defer { try? FileManager.default.removeItem(at: base) }

        let manager = VaultRootManager(
            bookmarks: StubBookmarkProvider(),
            validator: MusicRootValidator(applicationDataRoots: [])
        )
        var settings = try manager.replacingRoot(role: .active, with: active, in: .default)
        settings = try manager.replacingRoot(role: .archive, with: archive, in: settings)

        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertNotNil(settings.vault.activeRootID)
        XCTAssertNotNil(settings.vault.archiveRootID)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "VaultSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private struct StubBookmarkProvider: SecurityScopedBookmarkProviding {
    func makeBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
}
