import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// A1: multi-root bookmark recovery. Adapted from `.codex/audit-context.patch`
/// (`ArchiveMultiRootRecoveryAuditTests`) plus partial-success, later
/// recovery, and user-reselect/removal preservation.
@MainActor
final class ArchiveMultiRootRecoveryTests: XCTestCase {
    func testRecoveringFirstRootMustNotClearSecondAbsentFailure() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-audit-multiroot-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-audit-multiroot-second-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }

        let suiteName = "FeatureArchiveBrowserTests.MultiRoot.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        let runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.settingsSuiteKey: suiteName,
        ])
        let firstID = UUID()
        let secondID = UUID()
        try store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: firstID,
                    role: .scanOnly,
                    displayName: "First",
                    pathFallback: firstDir.path,
                    securityScopedBookmark: Data([0xA1])
                ),
                StoredMusicRoot(
                    id: secondID,
                    role: .scanOnly,
                    displayName: "Second",
                    pathFallback: secondDir.path,
                    securityScopedBookmark: Data([0xA2])
                ),
            ]
            settings.archiveOnboardingCompleted = true
        }

        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )

        XCTAssertTrue(viewModel.roots.isEmpty)
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, firstID)
        XCTAssertTrue(viewModel.showsArchiveAccessRecovery)
        XCTAssertFalse(viewModel.showsInlineArchiveAccessRecovery)

        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())

        XCTAssertFalse(
            viewModel.roots.contains(where: { $0.path == secondDir.standardizedFileURL.path }),
            "second root remains absent after recovering only the first"
        )
        XCTAssertNotNil(
            viewModel.archiveAccessFailure,
            "recovering the first root cleared the failure while the second root remains absent"
        )
        XCTAssertEqual(
            viewModel.archiveAccessFailure?.storedRootID, secondID,
            "remaining failure must identify the still-absent second root"
        )
        // Populated library must not use the empty overlay; inline strip stays actionable.
        XCTAssertFalse(viewModel.showsArchiveAccessRecovery)
        XCTAssertTrue(viewModel.showsInlineArchiveAccessRecovery)
        XCTAssertEqual(viewModel.storedArchiveAccessDirectory()?.path, secondDir.standardizedFileURL.path)
    }

    func testPartialSuccessPreservesAccessibleRootsAndBookmarkTokens() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let healthyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-healthy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: healthyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: healthyDir) }
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-second-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }
        let firstID = UUID()
        let secondID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: UUID(), role: .scanOnly, displayName: "Healthy", pathFallback: healthyDir.path, securityScopedBookmark: nil),
                StoredMusicRoot(id: firstID, role: .scanOnly, displayName: "First", pathFallback: firstDir.path, securityScopedBookmark: Data([0xA1])),
                StoredMusicRoot(id: secondID, role: .scanOnly, displayName: "Second", pathFallback: secondDir.path, securityScopedBookmark: Data([0xA2])),
            ]
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        // Healthy resolves via fallback; two bookmark failures collapse to first failure.
        XCTAssertEqual(viewModel.roots.map(\.path), [ArchiveBrowserViewModel.bookmarkKey(for: healthyDir)])
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, firstID)

        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())

        let keys = Set(viewModel.roots.map { ArchiveBrowserViewModel.bookmarkKey(for: $0) })
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: healthyDir)))
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: firstDir)))
        XCTAssertFalse(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: secondDir)))
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
        XCTAssertTrue(viewModel.showsInlineArchiveAccessRecovery)
        // Recovered token preserved in memory.
        XCTAssertEqual(viewModel.scanRootBookmarks[ArchiveBrowserViewModel.bookmarkKey(for: firstDir)], Data([0xA1]))
        // Persisted unresolved roots (with tokens) must survive the partial recovery.
        let persisted = try fixture.store.loadSettings()
        XCTAssertEqual(persisted.effectiveScanRoots.count, 3)
        XCTAssertEqual(persisted.effectiveScanRoots.first(where: { $0.id == firstID })?.securityScopedBookmark, Data([0xA1]))
        XCTAssertEqual(persisted.effectiveScanRoots.first(where: { $0.id == secondID })?.securityScopedBookmark, Data([0xA2]))
    }

    func testLaterRecoveryClearsFailureAfterSecondRetry() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-later-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-later-second-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }
        let firstID = UUID()
        let secondID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: firstID, role: .scanOnly, displayName: "First", pathFallback: firstDir.path, securityScopedBookmark: Data([0xA1])),
                StoredMusicRoot(id: secondID, role: .scanOnly, displayName: "Second", pathFallback: secondDir.path, securityScopedBookmark: Data([0xA2])),
            ]
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)

        provider.secondURL = secondDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertFalse(viewModel.showsArchiveAccessRecovery)
        XCTAssertFalse(viewModel.showsInlineArchiveAccessRecovery)
        let keys = Set(viewModel.roots.map { ArchiveBrowserViewModel.bookmarkKey(for: $0) })
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: firstDir)))
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: secondDir)))
    }

    func testUserReselectAddsNewRootWithoutDroppingUnresolved() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-reselect-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-reselect-second-\(UUID().uuidString)", isDirectory: true)
        let reselectDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-reselect-new-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reselectDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
            try? FileManager.default.removeItem(at: reselectDir)
        }
        let firstID = UUID()
        let secondID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: firstID, role: .scanOnly, displayName: "First", pathFallback: firstDir.path, securityScopedBookmark: Data([0xA1])),
                StoredMusicRoot(id: secondID, role: .scanOnly, displayName: "Second", pathFallback: secondDir.path, securityScopedBookmark: Data([0xA2])),
            ]
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)

        // User reselects an additional folder; unresolved second root must survive.
        viewModel.addRoots([reselectDir], bookmarksByURL: [reselectDir: Data([0xA9])])
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
        XCTAssertTrue(viewModel.showsInlineArchiveAccessRecovery)
        let persisted = try fixture.store.loadSettings()
        XCTAssertNotNil(persisted.effectiveScanRoots.first(where: { $0.id == secondID }))
        XCTAssertEqual(persisted.effectiveScanRoots.first(where: { $0.id == secondID })?.securityScopedBookmark, Data([0xA2]))
        XCTAssertNotNil(persisted.effectiveScanRoots.first(where: { $0.id == firstID }))
        // New root persisted with its token.
        XCTAssertTrue(persisted.effectiveScanRoots.contains(where: { $0.pathFallback == reselectDir.standardizedFileURL.path }))
    }

    func testRemovingOneRootPreservesUnresolvedPersistedRoots() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let healthyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-remove-healthy-\(UUID().uuidString)", isDirectory: true)
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-remove-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-remove-second-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: healthyDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: healthyDir)
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }
        let firstID = UUID()
        let secondID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: UUID(), role: .scanOnly, displayName: "Healthy", pathFallback: healthyDir.path, securityScopedBookmark: nil),
                StoredMusicRoot(id: firstID, role: .scanOnly, displayName: "First", pathFallback: firstDir.path, securityScopedBookmark: Data([0xA1])),
                StoredMusicRoot(id: secondID, role: .scanOnly, displayName: "Second", pathFallback: secondDir.path, securityScopedBookmark: Data([0xA2])),
            ]
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)

        // Remove the recovered first root; healthy stays, second unresolved stays persisted.
        let recoveredURL = viewModel.roots.first(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: firstDir) })
        let recovered = try XCTUnwrap(recoveredURL)
        viewModel.removeRoot(recovered)

        XCTAssertFalse(viewModel.roots.contains(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: firstDir) }))
        XCTAssertTrue(viewModel.roots.contains(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: healthyDir) }))
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
        let persisted = try fixture.store.loadSettings()
        XCTAssertNotNil(persisted.effectiveScanRoots.first(where: { $0.id == secondID }))
        XCTAssertEqual(persisted.effectiveScanRoots.first(where: { $0.id == secondID })?.securityScopedBookmark, Data([0xA2]))
    }

    func testRecoveringLastRootClearsStaleFooterWarning() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let healthyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-stale-healthy-\(UUID().uuidString)", isDirectory: true)
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-stale-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-stale-second-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: healthyDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: healthyDir)
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }
        let healthyID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: healthyID, role: .scanOnly, displayName: "Healthy", pathFallback: healthyDir.path, securityScopedBookmark: nil),
                StoredMusicRoot(id: firstID, role: .scanOnly, displayName: "Missing A", pathFallback: firstDir.path, securityScopedBookmark: Data([0xA1])),
                StoredMusicRoot(id: secondID, role: .scanOnly, displayName: "Missing B", pathFallback: secondDir.path, securityScopedBookmark: Data([0xA2])),
            ]
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, firstID)
        XCTAssertEqual(viewModel.persistenceWarningMessage, "Archive root access could not be restored: Missing A.")

        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
        XCTAssertEqual(viewModel.persistenceWarningMessage, "Archive root access could not be restored: Missing B.")
        XCTAssertTrue(viewModel.showsInlineArchiveAccessRecovery)

        provider.secondURL = secondDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertFalse(viewModel.showsInlineArchiveAccessRecovery)
        XCTAssertNil(viewModel.persistenceWarningMessage, "stale root-access footer must clear once the last failed root recovers")
        XCTAssertEqual(viewModel.statusMessage, "Scanning archive...")
        let keys = Set(viewModel.roots.map { ArchiveBrowserViewModel.bookmarkKey(for: $0) })
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: healthyDir)))
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: firstDir)))
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.bookmarkKey(for: secondDir)))
        let persisted = try fixture.store.loadSettings()
        XCTAssertEqual(Set(persisted.effectiveScanRoots.map(\.id)), Set([healthyID, firstID, secondID]))
        XCTAssertEqual(persisted.effectiveScanRoots.first(where: { $0.id == firstID })?.securityScopedBookmark, Data([0xA1]))
        XCTAssertEqual(persisted.effectiveScanRoots.first(where: { $0.id == secondID })?.securityScopedBookmark, Data([0xA2]))
    }

    func testRecoveringLastRootRetainsUnrelatedPersistenceWarning() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-unrelated-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-unrelated-second-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }
        let firstID = UUID()
        let secondID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: firstID, role: .scanOnly, displayName: "First", pathFallback: firstDir.path, securityScopedBookmark: Data([0xA1])),
                StoredMusicRoot(id: secondID, role: .scanOnly, displayName: "Second", pathFallback: secondDir.path, securityScopedBookmark: Data([0xA2])),
            ]
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
        XCTAssertEqual(viewModel.persistenceWarningMessage, "Archive root access could not be restored: Second.")

        viewModel.recordPersistenceWarning("Archive settings could not be saved: disk full.")
        provider.secondURL = secondDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertEqual(viewModel.persistenceWarningMessage, "Archive settings could not be saved: disk full.", "repair must not clear an unrelated warning")
        XCTAssertTrue(viewModel.statusMessage?.contains("Archive settings could not be saved") == true)
        XCTAssertFalse(viewModel.statusMessage?.contains("could not be restored") ?? false)
    }

    func testRemovingRootClearsOnlyStaleAccessWarning() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let healthyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-rmwarn-healthy-\(UUID().uuidString)", isDirectory: true)
        let firstDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-rmwarn-first-\(UUID().uuidString)", isDirectory: true)
        let secondDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-rmwarn-second-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: healthyDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: healthyDir)
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }
        let firstID = UUID()
        let secondID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: UUID(), role: .scanOnly, displayName: "Healthy", pathFallback: healthyDir.path, securityScopedBookmark: nil),
                StoredMusicRoot(id: firstID, role: .scanOnly, displayName: "First", pathFallback: firstDir.path, securityScopedBookmark: Data([0xA1])),
                StoredMusicRoot(id: secondID, role: .scanOnly, displayName: "Second", pathFallback: secondDir.path, securityScopedBookmark: Data([0xA2])),
            ]
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        provider.firstURL = firstDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)

        // Removing the recovered root keeps the remaining warning truthful.
        let recoveredURL = try XCTUnwrap(viewModel.roots.first(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: firstDir) }))
        viewModel.removeRoot(recoveredURL)
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
        XCTAssertEqual(viewModel.persistenceWarningMessage, "Archive root access could not be restored: Second.")

        // Recover the last root, then verify removal retains an unrelated warning.
        provider.secondURL = secondDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertNil(viewModel.persistenceWarningMessage)
        viewModel.recordPersistenceWarning("Archive settings could not be saved: disk full.")
        let healthyURL = try XCTUnwrap(viewModel.roots.first(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: healthyDir) }))
        viewModel.removeRoot(healthyURL)
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertEqual(viewModel.persistenceWarningMessage, "Archive settings could not be saved: disk full.", "removal must not clear an unrelated warning")
        XCTAssertTrue(viewModel.statusMessage?.contains("Archive settings could not be saved") == true)
    }

    func testVaultLinkedScanRootSurvivesAddAndReselect() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let vaultDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-vault-\(UUID().uuidString)", isDirectory: true)
        let healthyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-vault-healthy-\(UUID().uuidString)", isDirectory: true)
        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-vault-new-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: healthyDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: vaultDir)
            try? FileManager.default.removeItem(at: healthyDir)
            try? FileManager.default.removeItem(at: newDir)
        }
        let vaultID = UUID()
        let vaultBookmark = Data([0xB1])
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: vaultID, role: .scanOnly, displayName: "VaultArchive", pathFallback: vaultDir.path, securityScopedBookmark: vaultBookmark),
                StoredMusicRoot(id: UUID(), role: .scanOnly, displayName: "Healthy", pathFallback: healthyDir.path, securityScopedBookmark: nil),
            ]
            settings.vault.isEnabled = true
            settings.vault.archiveRootID = vaultID
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        provider.vaultURL = vaultDir
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        // Vault-linked scan root is valid but filtered out of browser roots.
        XCTAssertTrue(viewModel.roots.contains(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: healthyDir) }))
        XCTAssertFalse(viewModel.roots.contains(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: vaultDir) }))

        // Add/reselect another folder; vault-linked root must keep ID/bookmark.
        viewModel.addRoots([newDir], bookmarksByURL: [newDir: Data([0xA9])])
        var persisted = try fixture.store.loadSettings()
        var preserved = persisted.musicRoots.first(where: { $0.id == vaultID })
        XCTAssertNotNil(preserved, "vault-linked scan root must survive add/reselect persist")
        XCTAssertEqual(preserved?.securityScopedBookmark, vaultBookmark)
        XCTAssertEqual(preserved?.pathFallback, vaultDir.standardizedFileURL.path)

        // A second reselect must also preserve it.
        let anotherDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-vault-another-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: anotherDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: anotherDir) }
        viewModel.addRoot(anotherDir)
        persisted = try fixture.store.loadSettings()
        preserved = persisted.musicRoots.first(where: { $0.id == vaultID })
        XCTAssertNotNil(preserved, "vault-linked scan root must survive second reselect persist")
        XCTAssertEqual(preserved?.securityScopedBookmark, vaultBookmark)
    }

    func testVaultLinkedScanRootSurvivesRemove() throws {
        let fixture = try MultiRootFixture()
        defer { fixture.tearDown() }
        let vaultDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-vault-rm-\(UUID().uuidString)", isDirectory: true)
        let healthyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-vault-rm-healthy-\(UUID().uuidString)", isDirectory: true)
        let otherDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-multiroot-vault-rm-other-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: healthyDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: vaultDir)
            try? FileManager.default.removeItem(at: healthyDir)
            try? FileManager.default.removeItem(at: otherDir)
        }
        let vaultID = UUID()
        let vaultBookmark = Data([0xB1])
        let otherID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: vaultID, role: .scanOnly, displayName: "VaultArchive", pathFallback: vaultDir.path, securityScopedBookmark: vaultBookmark),
                StoredMusicRoot(id: UUID(), role: .scanOnly, displayName: "Healthy", pathFallback: healthyDir.path, securityScopedBookmark: nil),
                StoredMusicRoot(id: otherID, role: .scanOnly, displayName: "Other", pathFallback: otherDir.path, securityScopedBookmark: nil),
            ]
            settings.vault.isEnabled = true
            settings.vault.archiveRootID = vaultID
            settings.archiveOnboardingCompleted = true
        }
        let provider = MultiRootBookmarkProvider()
        provider.vaultURL = vaultDir
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        XCTAssertFalse(viewModel.roots.contains(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: vaultDir) }))

        let target = try XCTUnwrap(viewModel.roots.first(where: { ArchiveBrowserViewModel.bookmarkKey(for: $0) == ArchiveBrowserViewModel.bookmarkKey(for: otherDir) }))
        viewModel.removeRoot(target)

        let persisted = try fixture.store.loadSettings()
        let preserved = persisted.musicRoots.first(where: { $0.id == vaultID })
        XCTAssertNotNil(preserved, "vault-linked scan root must survive remove persist")
        XCTAssertEqual(preserved?.securityScopedBookmark, vaultBookmark)
        XCTAssertEqual(preserved?.pathFallback, vaultDir.standardizedFileURL.path)
        // Removed root is gone; healthy remains.
        XCTAssertNil(persisted.musicRoots.first(where: { $0.id == otherID }))
    }

    func testInlineRecoveryPreservesPopulatedLibraryLayout() throws {
        let browser = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift", encoding: .utf8)
        XCTAssertTrue(browser.contains("showsInlineArchiveAccessRecovery"))
        XCTAssertTrue(browser.contains("Choose Folder"))
        XCTAssertTrue(browser.contains("Grant Access"))
        // Empty overlay remains gated on empty roots; inline strip is the nonempty affordance.
        XCTAssertTrue(browser.contains("showsArchiveAccessRecovery"))
    }
}

private struct MultiRootFixture {
    let suiteName: String
    let store: UserDefaultsSettingsStore
    let runtime: MusicHubRuntimeEnvironment
    private let userDefaults: UserDefaults

    init() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        suiteName = "FeatureArchiveBrowserTests.MultiRoot.\(UUID())"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.settingsSuiteKey: suiteName,
        ])
    }

    func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

private final class MultiRootBookmarkProvider: SecurityScopedBookmarkProviding, SecurityScopedBookmarkResolving, @unchecked Sendable {
    var firstURL: URL?
    var secondURL: URL?
    var vaultURL: URL?

    func makeBookmark(for url: URL) throws -> Data { Data([0xA9]) }

    func resolveBookmark(_ data: Data) throws -> URL {
        if data == Data([0xA1]) {
            guard let firstURL else { throw SecurityScopedBookmarkError.staleBookmark }
            return firstURL
        }
        if data == Data([0xA2]) {
            guard let secondURL else { throw SecurityScopedBookmarkError.staleBookmark }
            return secondURL
        }
        if data == Data([0xB1]) {
            guard let vaultURL else { throw SecurityScopedBookmarkError.staleBookmark }
            return vaultURL
        }
        throw SecurityScopedBookmarkError.missingBookmark
    }
}
