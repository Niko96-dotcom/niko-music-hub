import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// A1-adjacent Vault Active root recovery.
///
/// Live bug: saved Active (role active, idA, invalid bookmark) + Archive
/// (role archive, idB) with vault enabled. Grant Access to the SAME Active
/// folder scanned but left the warning active and persisted a duplicate
/// scanOnly idC with the same canonical path instead of repairing idA
/// in place. These tests lock the repaired behavior.
@MainActor
final class ArchiveActiveRootRecoveryTests: XCTestCase {
    func testActiveReauthorizationRepairsBookmarkInPlaceAndAdvancesWarning() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let activeDir = try fixture.makeDirectory(prefix: "nmh-active-repair-active")
        let secondDir = try fixture.makeDirectory(prefix: "nmh-active-repair-second")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-repair-archive")
        defer {
            try? FileManager.default.removeItem(at: activeDir)
            try? FileManager.default.removeItem(at: secondDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let activeID = UUID()
        let secondID = UUID()
        let archiveID = UUID()
        let activeDisplayName = "My Active"
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: activeDisplayName,
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA1])
                ),
                StoredMusicRoot(
                    id: secondID,
                    role: .scanOnly,
                    displayName: "Second",
                    pathFallback: secondDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA2])
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
            ]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = activeDir
        // secondURL stays nil so the second scan root remains unresolved.
        let viewModel = fixture.makeViewModel(bookmarkProvider: provider)

        XCTAssertTrue(viewModel.roots.isEmpty)
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID)

        // Grant Access to the SAME Active folder with a fresh bookmark.
        let repairedBookmark = Data([0xC1])
        viewModel.addRoots([activeDir], bookmarksByURL: [activeDir: repairedBookmark])

        // In-place repair: same ID/role/display, vault refs untouched, no duplicate.
        let persisted = try fixture.store.loadSettings()
        let repaired = try XCTUnwrap(persisted.musicRoots.first(where: { $0.id == activeID }))
        XCTAssertEqual(repaired.role, .active)
        XCTAssertEqual(repaired.displayName, activeDisplayName)
        XCTAssertEqual(repaired.securityScopedBookmark, repairedBookmark)
        XCTAssertTrue(persisted.vault.isEnabled)
        XCTAssertEqual(persisted.vault.activeRootID, activeID)
        XCTAssertEqual(persisted.vault.archiveRootID, archiveID)
        let activeCanonical = ArchiveBrowserViewModel.canonicalPath(for: activeDir)
        let duplicates = persisted.musicRoots.filter {
            ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) == activeCanonical
        }
        XCTAssertEqual(duplicates.map(\.id), [activeID], "same canonical path must not mint a duplicate scanOnly")
        XCTAssertFalse(persisted.musicRoots.contains(where: { $0.role == .scanOnly && ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) == activeCanonical }))

        // Unrelated roots preserved with tokens.
        XCTAssertEqual(persisted.musicRoots.first(where: { $0.id == secondID })?.securityScopedBookmark, Data([0xA2]))
        XCTAssertNotNil(persisted.musicRoots.first(where: { $0.id == archiveID }))

        // Warning advances to the second unresolved root; populated library uses inline strip.
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
        XCTAssertFalse(viewModel.showsArchiveAccessRecovery)
        XCTAssertTrue(viewModel.showsInlineArchiveAccessRecovery)
        XCTAssertTrue(viewModel.roots.contains(where: { ArchiveBrowserViewModel.canonicalPath(for: $0) == activeCanonical }))

        // Recovering the second root clears the failure without touching the repaired Active.
        provider.secondURL = secondDir
        XCTAssertTrue(viewModel.retryStoredArchiveAccess())
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertFalse(viewModel.showsInlineArchiveAccessRecovery)
        let repersisted = try fixture.store.loadSettings()
        XCTAssertEqual(repersisted.musicRoots.first(where: { $0.id == activeID })?.securityScopedBookmark, repairedBookmark)
        XCTAssertEqual(repersisted.musicRoots.first(where: { $0.id == activeID })?.role, .active)
        XCTAssertEqual(repersisted.vault.activeRootID, activeID)
        XCTAssertEqual(repersisted.vault.archiveRootID, archiveID)
        let keys = Set(viewModel.roots.map { ArchiveBrowserViewModel.canonicalPath(for: $0) })
        XCTAssertTrue(keys.contains(activeCanonical))
        XCTAssertTrue(keys.contains(ArchiveBrowserViewModel.canonicalPath(for: secondDir)))
    }

    func testActiveReauthorizationIsCanonicalAliasAware() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let realDir = try fixture.makeDirectory(prefix: "nmh-active-alias-active")
        let secondDir = try fixture.makeDirectory(prefix: "nmh-active-alias-second")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-alias-archive")
        defer {
            try? FileManager.default.removeItem(at: realDir)
            try? FileManager.default.removeItem(at: secondDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let standardizedURL = realDir.standardizedFileURL
        let canonicalURL = realDir.resolvingSymlinksInPath().standardizedFileURL
        XCTAssertEqual(
            ArchiveBrowserViewModel.canonicalPath(for: standardizedURL),
            ArchiveBrowserViewModel.canonicalPath(for: canonicalURL),
            "fixture must compare the same folder through both path forms"
        )
        // Store one form, reauthorize through the other to prove alias awareness.
        let storedFallbackPath = canonicalURL.path
        let reselectURL = standardizedURL

        let activeID = UUID()
        let secondID = UUID()
        let archiveID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: "Active",
                    pathFallback: storedFallbackPath,
                    securityScopedBookmark: Data([0xA1])
                ),
                StoredMusicRoot(
                    id: secondID,
                    role: .scanOnly,
                    displayName: "Second",
                    pathFallback: secondDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA2])
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
            ]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = realDir
        let viewModel = fixture.makeViewModel(bookmarkProvider: provider)
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID)

        viewModel.addRoots([reselectURL], bookmarksByURL: [reselectURL: Data([0xC1])])

        let persisted = try fixture.store.loadSettings()
        let repaired = try XCTUnwrap(persisted.musicRoots.first(where: { $0.id == activeID }))
        XCTAssertEqual(repaired.securityScopedBookmark, Data([0xC1]))
        XCTAssertEqual(repaired.role, .active)
        let activeCanonical = ArchiveBrowserViewModel.canonicalPath(for: realDir)
        let duplicates = persisted.musicRoots.filter {
            ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) == activeCanonical
        }
        XCTAssertEqual(duplicates.map(\.id), [activeID], "canonical alias must not mint a duplicate scanOnly")
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, secondID)
    }

    func testDifferentFolderDoesNotReassignVaultBinding() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let activeDir = try fixture.makeDirectory(prefix: "nmh-active-different-active")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-different-archive")
        let otherDir = try fixture.makeDirectory(prefix: "nmh-active-different-other")
        defer {
            try? FileManager.default.removeItem(at: activeDir)
            try? FileManager.default.removeItem(at: archiveDir)
            try? FileManager.default.removeItem(at: otherDir)
        }

        let activeID = UUID()
        let archiveID = UUID()
        let originalBookmark = Data([0xA1])
        let originalFallback = activeDir.standardizedFileURL.path
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: "Active",
                    pathFallback: originalFallback,
                    securityScopedBookmark: originalBookmark
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
            ]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = activeDir
        provider.extraURL = otherDir
        let viewModel = fixture.makeViewModel(bookmarkProvider: provider)
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID)

        // Choosing a DIFFERENT folder is an additional scan root, never a silent
        // Vault reassignment (fail closed).
        viewModel.addRoots([otherDir], bookmarksByURL: [otherDir: Data([0xD1])])

        let persisted = try fixture.store.loadSettings()
        let preservedActive = try XCTUnwrap(persisted.musicRoots.first(where: { $0.id == activeID }))
        XCTAssertEqual(preservedActive.role, .active)
        XCTAssertEqual(preservedActive.securityScopedBookmark, originalBookmark, "different folder must not overwrite the Vault bookmark")
        XCTAssertEqual(preservedActive.pathFallback, originalFallback)
        XCTAssertEqual(persisted.vault.activeRootID, activeID)
        XCTAssertEqual(persisted.vault.archiveRootID, archiveID)
        XCTAssertTrue(persisted.musicRoots.contains(where: {
            $0.role == .scanOnly && ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) == ArchiveBrowserViewModel.canonicalPath(for: otherDir)
        }))
        // Original Active remains the actionable failure.
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID)
        XCTAssertTrue(viewModel.showsInlineArchiveAccessRecovery)
    }

    func testPersistenceFailurePreservesActionableRecovery() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let activeDir = try fixture.makeDirectory(prefix: "nmh-active-persist-active")
        let secondDir = try fixture.makeDirectory(prefix: "nmh-active-persist-second")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-persist-archive")
        defer {
            try? FileManager.default.removeItem(at: activeDir)
            try? FileManager.default.removeItem(at: secondDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let activeID = UUID()
        let secondID = UUID()
        let archiveID = UUID()
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: "Active",
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA1])
                ),
                StoredMusicRoot(
                    id: secondID,
                    role: .scanOnly,
                    displayName: "Second",
                    pathFallback: secondDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA2])
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
            ]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let backing = fixture.store
        let failing = FailingUpdateSettingsStore(backing: backing)
        failing.failUpdates = true
        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = activeDir
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: failing),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: fixture.runtime,
            bookmarkProvider: provider,
            scanOverride: { _ in ScanResult() }
        )
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID)

        viewModel.addRoots([activeDir], bookmarksByURL: [activeDir: Data([0xC1])])

        // Persist failed: the stored Active keeps its original token (never
        // discarded), vault binding is untouched, and recovery stays actionable.
        let stillPersisted = try backing.loadSettings()
        XCTAssertEqual(stillPersisted.musicRoots.first(where: { $0.id == activeID })?.securityScopedBookmark, Data([0xA1]))
        XCTAssertEqual(stillPersisted.vault.activeRootID, activeID)
        XCTAssertEqual(stillPersisted.vault.archiveRootID, archiveID)
        XCTAssertFalse(stillPersisted.musicRoots.contains(where: {
            $0.role == .scanOnly && ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) == ArchiveBrowserViewModel.canonicalPath(for: activeDir)
        }), "failed persist must not leave a duplicate scanOnly behind")
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID, "failed persist must keep the Active recovery actionable")
        XCTAssertNotNil(viewModel.persistenceWarningMessage)
        // Fresh in-memory bookmark is retained for the next attempt, not discarded.
        XCTAssertEqual(viewModel.scanRootBookmarks[ArchiveBrowserViewModel.bookmarkKey(for: activeDir)], Data([0xC1]))

        // A later successful persist repairs in place with no duplicate.
        failing.failUpdates = false
        viewModel.persistRoots()
        let repaired = try backing.loadSettings()
        XCTAssertEqual(repaired.musicRoots.first(where: { $0.id == activeID })?.securityScopedBookmark, Data([0xC1]))
        let activeCanonical = ArchiveBrowserViewModel.canonicalPath(for: activeDir)
        XCTAssertEqual(
            repaired.musicRoots.filter { ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) == activeCanonical }.map(\.id),
            [activeID]
        )
    }

    func testSameFolderReauthorizationRepairsWhenRootsAlreadyContainsDuplicateCanonical() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let activeDir = try fixture.makeDirectory(prefix: "nmh-active-dup-active")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-dup-archive")
        defer {
            try? FileManager.default.removeItem(at: activeDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let activeID = UUID()
        let archiveID = UUID()
        let duplicateID = UUID()
        let activeDisplayName = "My Active"
        let duplicateBookmark = Data([0xE1])
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: activeDisplayName,
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA1])
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
                StoredMusicRoot(
                    id: duplicateID,
                    role: .scanOnly,
                    displayName: activeDir.lastPathComponent,
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: duplicateBookmark
                ),
            ]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = activeDir
        let viewModel = fixture.makeViewModel(bookmarkProvider: provider)
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID)

        // Live old-bug relaunch: `roots` already contains the same canonical via
        // the erroneous enabled duplicate scanOnly, so the plain `addRoots` guard
        // would previously no-op and never persist the repair.
        viewModel.roots = [activeDir.standardizedFileURL]
        viewModel.scanRootBookmarks[ArchiveBrowserViewModel.bookmarkKey(for: activeDir)] = duplicateBookmark

        let freshBookmark = Data([0xC1])
        viewModel.addRoots([activeDir], bookmarksByURL: [activeDir: freshBookmark])

        let persisted = try fixture.store.loadSettings()
        let repaired = try XCTUnwrap(persisted.musicRoots.first(where: { $0.id == activeID }))
        XCTAssertEqual(repaired.role, .active)
        XCTAssertEqual(repaired.displayName, activeDisplayName)
        XCTAssertEqual(repaired.securityScopedBookmark, freshBookmark)
        XCTAssertTrue(persisted.vault.isEnabled)
        XCTAssertEqual(persisted.vault.activeRootID, activeID)
        XCTAssertEqual(persisted.vault.archiveRootID, archiveID)
        let activeCanonical = ArchiveBrowserViewModel.canonicalPath(for: activeDir)
        XCTAssertEqual(
            persisted.musicRoots.filter { ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) == activeCanonical }.map(\.id),
            [activeID],
            "enabled duplicate scanOnly must be removed, original Vault root retained"
        )
        XCTAssertFalse(persisted.musicRoots.contains(where: { $0.id == duplicateID }))
        XCTAssertNotNil(persisted.musicRoots.first(where: { $0.id == archiveID }))
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertFalse(viewModel.showsInlineArchiveAccessRecovery)
        XCTAssertTrue(viewModel.roots.contains(where: { ArchiveBrowserViewModel.canonicalPath(for: $0) == activeCanonical }))
    }

    func testDisabledScanOnlySameCanonicalIsPreservedThroughVaultRepair() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let activeDir = try fixture.makeDirectory(prefix: "nmh-active-disabled-active")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-disabled-archive")
        defer {
            try? FileManager.default.removeItem(at: activeDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let activeID = UUID()
        let archiveID = UUID()
        let disabledID = UUID()
        let disabledBookmark = Data([0xE2])
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: "Active",
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA1])
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
                StoredMusicRoot(
                    id: disabledID,
                    role: .scanOnly,
                    displayName: "Disabled duplicate",
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: disabledBookmark,
                    isEnabled: false
                ),
            ]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = activeDir
        let viewModel = fixture.makeViewModel(bookmarkProvider: provider)
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, activeID)

        viewModel.addRoots([activeDir], bookmarksByURL: [activeDir: Data([0xC1])])

        let persisted = try fixture.store.loadSettings()
        let repaired = try XCTUnwrap(persisted.musicRoots.first(where: { $0.id == activeID }))
        XCTAssertEqual(repaired.securityScopedBookmark, Data([0xC1]))
        XCTAssertEqual(repaired.role, .active)
        let preservedDisabled = try XCTUnwrap(
            persisted.musicRoots.first(where: { $0.id == disabledID }),
            "disabled scanOnly must never be discarded merely for dedup"
        )
        XCTAssertEqual(preservedDisabled.securityScopedBookmark, disabledBookmark)
        XCTAssertFalse(preservedDisabled.isEnabled)
        XCTAssertEqual(preservedDisabled.role, .scanOnly)
        XCTAssertEqual(persisted.vault.activeRootID, activeID)
        XCTAssertEqual(persisted.vault.archiveRootID, archiveID)
    }

    func testVaultOffSameFolderPairPreservesEffectiveScanOnlyThroughOrdinaryPersist() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let activeDir = try fixture.makeDirectory(prefix: "nmh-active-vaultoff-active")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-vaultoff-archive")
        defer {
            try? FileManager.default.removeItem(at: activeDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let activeID = UUID()
        let archiveID = UUID()
        let scanOnlyID = UUID()
        let scanOnlyBookmark = Data([0xE1])
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: "Active",
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: Data([0xA1])
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
                StoredMusicRoot(
                    id: scanOnlyID,
                    role: .scanOnly,
                    displayName: activeDir.lastPathComponent,
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: scanOnlyBookmark
                ),
            ]
            settings.vault.isEnabled = false
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = activeDir
        let viewModel = fixture.makeViewModel(bookmarkProvider: provider)
        let activeCanonical = ArchiveBrowserViewModel.canonicalPath(for: activeDir)
        XCTAssertTrue(
            viewModel.roots.contains(where: { ArchiveBrowserViewModel.canonicalPath(for: $0) == activeCanonical }),
            "vault-off browsing must still show the scanOnly library root"
        )

        // Ordinary persist (no same-folder repair): must not drop the only effective root.
        viewModel.persistRoots()

        let persisted = try fixture.store.loadSettings()
        let preservedScanOnly = try XCTUnwrap(
            persisted.musicRoots.first(where: { $0.id == scanOnlyID }),
            "vault-off persist must preserve the enabled scanOnly record"
        )
        XCTAssertEqual(preservedScanOnly.securityScopedBookmark, scanOnlyBookmark)
        XCTAssertTrue(preservedScanOnly.isEnabled)
        XCTAssertNotNil(persisted.musicRoots.first(where: { $0.id == activeID }))
        let effectiveCanonicals = Set(
            persisted.effectiveScanRoots.map { ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) }
        )
        XCTAssertTrue(
            effectiveCanonicals.contains(activeCanonical),
            "effectiveScanRoots after vault-off persist must still contain the library folder"
        )

        // Reload must not silently lose the library root.
        let reloaded = fixture.makeViewModel(bookmarkProvider: provider)
        XCTAssertTrue(
            reloaded.roots.contains(where: { ArchiveBrowserViewModel.canonicalPath(for: $0) == activeCanonical }),
            "reload after vault-off persist must still show the library root"
        )
    }

    func testDisabledActiveSameFolderPairPreservesEnabledScanOnlyThroughOrdinaryPersist() throws {
        let fixture = try ActiveRecoveryFixture()
        defer { fixture.tearDown() }
        let activeDir = try fixture.makeDirectory(prefix: "nmh-active-disabledvault-active")
        let archiveDir = try fixture.makeDirectory(prefix: "nmh-active-disabledvault-archive")
        defer {
            try? FileManager.default.removeItem(at: activeDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let activeID = UUID()
        let archiveID = UUID()
        let scanOnlyID = UUID()
        let scanOnlyBookmark = Data([0xE1])
        let disabledActiveBookmark = Data([0xA1])
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(
                    id: activeID,
                    role: .active,
                    displayName: "Active",
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: disabledActiveBookmark,
                    isEnabled: false
                ),
                StoredMusicRoot(
                    id: archiveID,
                    role: .archive,
                    displayName: "Archive",
                    pathFallback: archiveDir.standardizedFileURL.path,
                    securityScopedBookmark: nil
                ),
                StoredMusicRoot(
                    id: scanOnlyID,
                    role: .scanOnly,
                    displayName: activeDir.lastPathComponent,
                    pathFallback: activeDir.standardizedFileURL.path,
                    securityScopedBookmark: scanOnlyBookmark
                ),
            ]
            settings.vault.isEnabled = true
            settings.vault.activeRootID = activeID
            settings.vault.archiveRootID = archiveID
            settings.archiveOnboardingCompleted = true
        }

        let provider = ActiveRecoveryBookmarkProvider()
        provider.activeURL = activeDir
        let viewModel = fixture.makeViewModel(bookmarkProvider: provider)
        let activeCanonical = ArchiveBrowserViewModel.canonicalPath(for: activeDir)
        XCTAssertTrue(
            viewModel.roots.contains(where: { ArchiveBrowserViewModel.canonicalPath(for: $0) == activeCanonical }),
            "disabled Active must not hide the enabled scanOnly library root"
        )

        // Ordinary persist: a disabled Vault root must neither shadow nor delete the enabled scanOnly.
        viewModel.persistRoots()

        let persisted = try fixture.store.loadSettings()
        let preservedScanOnly = try XCTUnwrap(
            persisted.musicRoots.first(where: { $0.id == scanOnlyID }),
            "disabled-Active persist must preserve the enabled scanOnly record"
        )
        XCTAssertEqual(preservedScanOnly.securityScopedBookmark, scanOnlyBookmark)
        XCTAssertTrue(preservedScanOnly.isEnabled)
        let preservedDisabledActive = try XCTUnwrap(persisted.musicRoots.first(where: { $0.id == activeID }))
        XCTAssertFalse(preservedDisabledActive.isEnabled)
        XCTAssertEqual(
            preservedDisabledActive.securityScopedBookmark,
            disabledActiveBookmark,
            "disabled Vault root must not be repaired from the scanOnly snapshot"
        )
        let effectiveCanonicals = Set(
            persisted.effectiveScanRoots.map { ArchiveBrowserViewModel.canonicalPath(for: $0.fallbackURL) }
        )
        XCTAssertTrue(
            effectiveCanonicals.contains(activeCanonical),
            "effectiveScanRoots after disabled-Active persist must still contain the library folder"
        )

        // Reload must not silently lose the library root.
        let reloaded = fixture.makeViewModel(bookmarkProvider: provider)
        XCTAssertTrue(
            reloaded.roots.contains(where: { ArchiveBrowserViewModel.canonicalPath(for: $0) == activeCanonical }),
            "reload after disabled-Active persist must still show the library root"
        )
    }
}

private struct ActiveRecoveryFixture {
    let suiteName: String
    let store: UserDefaultsSettingsStore
    let runtime: MusicHubRuntimeEnvironment
    private let userDefaults: UserDefaults

    init() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        suiteName = "FeatureArchiveBrowserTests.ActiveRecovery.\(UUID())"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.settingsSuiteKey: suiteName,
        ])
    }

    func makeDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func makeViewModel(bookmarkProvider: any SecurityScopedBookmarkProviding) -> ArchiveBrowserViewModel {
        ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: runtime,
            bookmarkProvider: bookmarkProvider,
            scanOverride: { _ in ScanResult() }
        )
    }

    func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

private final class ActiveRecoveryBookmarkProvider: SecurityScopedBookmarkProviding, SecurityScopedBookmarkResolving, @unchecked Sendable {
    var activeURL: URL?
    var secondURL: URL?
    var extraURL: URL?

    func makeBookmark(for url: URL) throws -> Data { Data([0xC9]) }

    func resolveBookmark(_ data: Data) throws -> URL {
        if data == Data([0xA1]) {
            throw SecurityScopedBookmarkError.staleBookmark
        }
        if data == Data([0xC1]) {
            guard let activeURL else { throw SecurityScopedBookmarkError.staleBookmark }
            return activeURL
        }
        if data == Data([0xE1]) {
            guard let activeURL else { throw SecurityScopedBookmarkError.staleBookmark }
            return activeURL
        }
        if data == Data([0xA2]) {
            guard let secondURL else { throw SecurityScopedBookmarkError.staleBookmark }
            return secondURL
        }
        if data == Data([0xD1]) {
            guard let extraURL else { throw SecurityScopedBookmarkError.staleBookmark }
            return extraURL
        }
        throw SecurityScopedBookmarkError.missingBookmark
    }
}

private final class FailingUpdateSettingsStore: SettingsStore, @unchecked Sendable {
    private let backing: UserDefaultsSettingsStore
    var failUpdates = false

    init(backing: UserDefaultsSettingsStore) {
        self.backing = backing
    }

    func loadSettings() throws -> AppSettings {
        try backing.loadSettings()
    }

    func saveSettings(_ settings: AppSettings) throws {
        try backing.saveSettings(settings)
    }

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        if failUpdates {
            throw ActiveRecoveryPersistenceError.forced
        }
        try backing.updateSettings(update)
    }
}

private enum ActiveRecoveryPersistenceError: LocalizedError {
    case forced

    var errorDescription: String? {
        "forced persistence failure"
    }
}
