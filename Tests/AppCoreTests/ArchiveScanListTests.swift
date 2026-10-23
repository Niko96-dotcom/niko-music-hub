import AppCore
import Foundation
import NikoMusicCore
import XCTest

/// The scan-list edits on plain settings values. The archive's own suites
/// (`ArchiveActiveRootRecoveryTests`, `ArchiveMultiRootRecoveryTests`,
/// `ArchiveAccessRecoveryTests`) drive the same edits through the view model.
final class ArchiveScanListTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
        super.tearDown()
    }

    // MARK: - Adding

    func testAddingANewFolderStoresAScanOnlyRecordAndCompletesOnboarding() throws {
        let folder = try makeFolder("new")
        let added = ArchiveScanList(bookmarks: StubResolver()).adding(folder, bookmark: Data([1]), to: AppSettings())

        let record = try XCTUnwrap(added.musicRoots.only)
        XCTAssertEqual(record.role, .scanOnly)
        XCTAssertTrue(record.isEnabled)
        XCTAssertEqual(record.pathFallback, folder.standardizedFileURL.path)
        XCTAssertEqual(record.securityScopedBookmark, Data([1]))
        XCTAssertTrue(added.archiveOnboardingCompleted)
    }

    func testAddingTheSameFolderByAnotherSpellingKeepsItsRecordAndTakesTheNewBookmark() throws {
        let folder = try makeFolder("alias")
        // The temporary directory sits behind `/var` → `/private/var`; store the
        // `/private` spelling and add the short one.
        let privateSpelling = URL(fileURLWithPath: "/private" + folder.standardizedFileURL.path, isDirectory: true)
        XCTAssertTrue(folder.standardizedFileURL.path.hasPrefix("/var/"), "fixture must use two spellings")
        XCTAssertEqual(ArchiveScanList.canonicalPath(for: privateSpelling), ArchiveScanList.canonicalPath(for: folder))
        let stored = StoredMusicRoot(role: .scanOnly, url: privateSpelling, securityScopedBookmark: Data([1]))
        var settings = AppSettings()
        settings.musicRoots = [stored]

        let added = ArchiveScanList(bookmarks: StubResolver()).adding(folder, bookmark: Data([2]), to: settings)

        XCTAssertEqual(added.musicRoots.map(\.id), [stored.id])
        XCTAssertEqual(added.musicRoots.first?.securityScopedBookmark, Data([2]))
    }

    func testAddingAMovedFolderMatchesTheRecordWhoseBookmarkPointsThere() throws {
        let movedTo = try makeFolder("moved")
        let stored = StoredMusicRoot(
            role: .scanOnly,
            displayName: "Old",
            pathFallback: "/nmh-scan-list/old-location",
            securityScopedBookmark: Data([7])
        )
        var settings = AppSettings()
        settings.musicRoots = [stored]

        let added = ArchiveScanList(bookmarks: StubResolver([Data([7]): movedTo]))
            .adding(movedTo, bookmark: nil, to: settings)

        XCTAssertEqual(added.musicRoots, [stored], "no duplicate; a missing new bookmark keeps the stored one")
    }

    func testAddingTheFolderOfTheVaultActiveRootRepairsItInPlace() throws {
        let activeFolder = try makeFolder("active")
        var settings = vaultSettings(activeFolder: activeFolder, archiveFolder: try makeFolder("archive"))
        let active = try XCTUnwrap(settings.musicRoots.first { $0.role == .active })
        let enabledDuplicate = StoredMusicRoot(role: .scanOnly, url: activeFolder, securityScopedBookmark: Data([0xE1]))
        let disabledDuplicate = StoredMusicRoot(
            role: .scanOnly,
            url: activeFolder,
            securityScopedBookmark: Data([0xE2]),
            isEnabled: false
        )
        settings.musicRoots += [enabledDuplicate, disabledDuplicate]

        let added = ArchiveScanList(bookmarks: StubResolver()).adding(activeFolder, bookmark: Data([0xC1]), to: settings)

        let repaired = try XCTUnwrap(added.musicRoots.first { $0.id == active.id })
        XCTAssertEqual(repaired.role, .active)
        XCTAssertEqual(repaired.displayName, active.displayName)
        XCTAssertEqual(repaired.securityScopedBookmark, Data([0xC1]))
        XCTAssertEqual(added.vault, settings.vault, "the Vault binding stays")
        XCTAssertNil(added.musicRoots.first { $0.id == enabledDuplicate.id }, "the enabled duplicate goes")
        XCTAssertEqual(added.musicRoots.first { $0.id == disabledDuplicate.id }, disabledDuplicate, "a disabled record stays")
    }

    func testAddingADifferentFolderNeverRebindsAVaultRoot() throws {
        let settings = vaultSettings(activeFolder: try makeFolder("active"), archiveFolder: try makeFolder("archive"))
        let other = try makeFolder("other")

        let added = ArchiveScanList(bookmarks: StubResolver()).adding(other, bookmark: Data([0xD1]), to: settings)

        XCTAssertEqual(Array(added.musicRoots.prefix(2)), settings.musicRoots, "Vault roots unchanged")
        XCTAssertEqual(added.vault, settings.vault)
        let new = try XCTUnwrap(added.musicRoots.last)
        XCTAssertEqual(new.role, .scanOnly)
        XCTAssertEqual(new.pathFallback, other.standardizedFileURL.path)
    }

    func testAddingWithVaultOffTreatsTheActiveFolderAsAScanFolder() throws {
        let activeFolder = try makeFolder("active")
        var settings = vaultSettings(activeFolder: activeFolder, archiveFolder: try makeFolder("archive"))
        settings.vault.isEnabled = false
        let scanOnly = StoredMusicRoot(role: .scanOnly, url: activeFolder, securityScopedBookmark: Data([0xE1]))
        settings.musicRoots.append(scanOnly)

        let added = ArchiveScanList(bookmarks: StubResolver()).adding(activeFolder, bookmark: Data([0xC1]), to: settings)

        XCTAssertEqual(added.musicRoots.first { $0.role == .active }, settings.musicRoots.first { $0.role == .active })
        XCTAssertEqual(added.musicRoots.first { $0.id == scanOnly.id }?.securityScopedBookmark, Data([0xC1]))
        XCTAssertEqual(added.musicRoots.count, settings.musicRoots.count)
    }

    func testAddingAFolderWhoseOnlyRecordIsDisabledAddsAnEnabledRecord() throws {
        let folder = try makeFolder("disabled")
        let disabled = StoredMusicRoot(role: .scanOnly, url: folder, securityScopedBookmark: Data([1]), isEnabled: false)
        var settings = AppSettings()
        settings.musicRoots = [disabled]

        let added = ArchiveScanList(bookmarks: StubResolver()).adding(folder, bookmark: Data([2]), to: settings)

        XCTAssertEqual(added.musicRoots.first, disabled)
        XCTAssertEqual(added.musicRoots.count, 2)
        XCTAssertEqual(added.musicRoots.last?.isEnabled, true)
        XCTAssertEqual(added.musicRoots.last?.securityScopedBookmark, Data([2]))
    }

    // MARK: - Removing

    func testRemovingAFolderKeepsEveryOtherRecord() throws {
        let folder = try makeFolder("remove")
        var settings = vaultSettings(activeFolder: try makeFolder("active"), archiveFolder: try makeFolder("archive"))
        let target = StoredMusicRoot(role: .scanOnly, url: folder)
        let disabledTwin = StoredMusicRoot(role: .scanOnly, url: folder, isEnabled: false)
        let failedOther = StoredMusicRoot(
            role: .scanOnly,
            displayName: "Failed",
            pathFallback: "/nmh-scan-list/failed",
            securityScopedBookmark: Data([9])
        )
        settings.musicRoots += [target, disabledTwin, failedOther]

        let removed = ArchiveScanList(bookmarks: StubResolver()).removing(folder, from: settings)

        XCTAssertEqual(removed.musicRoots, settings.musicRoots.filter { $0.id != target.id })
        XCTAssertEqual(removed.vault, settings.vault)
    }

    func testRemovingAFolderWhoseAccessFailedRemovesIt() {
        let failed = StoredMusicRoot(
            role: .scanOnly,
            displayName: "Gone",
            pathFallback: "/nmh-scan-list/gone",
            securityScopedBookmark: Data([9])
        )
        var settings = AppSettings()
        settings.musicRoots = [failed]

        let removed = ArchiveScanList(bookmarks: StubResolver()).removing(failed.fallbackURL, from: settings)

        XCTAssertTrue(removed.musicRoots.isEmpty)
    }

    func testRemovingAMovedFolderMatchesTheRecordWhoseBookmarkPointsThere() throws {
        let movedTo = try makeFolder("moved")
        var settings = AppSettings()
        settings.musicRoots = [
            StoredMusicRoot(role: .scanOnly, displayName: "Old", pathFallback: "/nmh-scan-list/old", securityScopedBookmark: Data([7])),
        ]

        let removed = ArchiveScanList(bookmarks: StubResolver([Data([7]): movedTo])).removing(movedTo, from: settings)

        XCTAssertTrue(removed.musicRoots.isEmpty)
    }

    func testRemovingTheVaultActiveFolderChangesNothing() throws {
        let activeFolder = try makeFolder("active")
        let settings = vaultSettings(activeFolder: activeFolder, archiveFolder: try makeFolder("archive"))

        let removed = ArchiveScanList(bookmarks: StubResolver()).removing(activeFolder, from: settings)

        XCTAssertEqual(removed, settings)
    }

    func testTheVaultArchiveBindingStaysWhileVaultIsOn() throws {
        let bound = try makeFolder("bound")
        let binding = StoredMusicRoot(role: .scanOnly, url: bound)
        var settings = AppSettings()
        settings.musicRoots = [binding]
        settings.vault.archiveRootID = binding.id
        let scanList = ArchiveScanList(bookmarks: StubResolver())

        settings.vault.isEnabled = true
        XCTAssertEqual(scanList.removing(bound, from: settings).musicRoots, [binding])
        settings.vault.isEnabled = false
        XCTAssertTrue(scanList.removing(bound, from: settings).musicRoots.isEmpty)
    }

    // MARK: - Scanned roots

    func testScannedRootsFollowTheVaultSwitch() throws {
        var settings = vaultSettings(activeFolder: try makeFolder("active"), archiveFolder: try makeFolder("archive"))
        let scanOnly = StoredMusicRoot(role: .scanOnly, url: try makeFolder("scan"))
        let disabled = StoredMusicRoot(role: .scanOnly, url: try makeFolder("off"), isEnabled: false)
        settings.musicRoots += [scanOnly, disabled]
        let active = try XCTUnwrap(settings.musicRoots.first { $0.role == .active })

        settings.vault.isEnabled = true
        XCTAssertEqual(ArchiveScanList.scannedRoots(in: settings).map(\.id), [active.id, scanOnly.id])
        settings.vault.isEnabled = false
        XCTAssertEqual(ArchiveScanList.scannedRoots(in: settings).map(\.id), [scanOnly.id])
    }

    // MARK: - Helpers

    private func makeFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-scan-list-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        return url
    }

    /// Vault on with an Active root (bookmark that no longer resolves) and an
    /// Archive root, in that order.
    private func vaultSettings(activeFolder: URL, archiveFolder: URL) -> AppSettings {
        let active = StoredMusicRoot(role: .active, displayName: "My Active", pathFallback: activeFolder.standardizedFileURL.path, securityScopedBookmark: Data([0xA1]))
        let archive = StoredMusicRoot(role: .archive, url: archiveFolder)
        var settings = AppSettings()
        settings.musicRoots = [active, archive]
        settings.vault.isEnabled = true
        settings.vault.activeRootID = active.id
        settings.vault.archiveRootID = archive.id
        return settings
    }
}

private struct StubResolver: SecurityScopedBookmarkResolving {
    var locations: [Data: URL] = [:]

    init(_ locations: [Data: URL] = [:]) {
        self.locations = locations
    }

    func resolveBookmark(_ data: Data) throws -> URL {
        guard let url = locations[data] else { throw SecurityScopedBookmarkError.staleBookmark }
        return url
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
