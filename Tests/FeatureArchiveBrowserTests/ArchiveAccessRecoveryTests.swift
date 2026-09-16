import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveAccessRecoveryTests: XCTestCase {
    func testStaleBookmarkShowsAccessRecoveryNotEmptyLibrary() throws {
        let fixture = try IsolatedArchiveSettingsFixture()
        defer { fixture.tearDown() }

        let rootID = UUID()
        let stored = StoredMusicRoot(
            id: rootID,
            role: .scanOnly,
            displayName: "Fixture Archive",
            pathFallback: fixture.nonMusicVaultPath,
            securityScopedBookmark: Data([0x00, 0x01, 0x02])
        )
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [stored]
            settings.archiveOnboardingCompleted = true
        }

        let viewModel = fixture.makeViewModel()

        XCTAssertTrue(viewModel.roots.isEmpty)
        XCTAssertTrue(viewModel.songs.isEmpty)
        XCTAssertFalse(viewModel.needsFirstRunOnboarding)
        XCTAssertNotNil(viewModel.archiveAccessFailure)
        XCTAssertEqual(viewModel.archiveAccessFailure?.displayName, "Fixture Archive")
        XCTAssertEqual(viewModel.archiveAccessFailure?.storedRootID, rootID)
        XCTAssertFalse(viewModel.archiveAccessFailure?.reason.isEmpty ?? true)
        XCTAssertTrue(viewModel.showsArchiveAccessRecovery)
        let recoveryMessage = try XCTUnwrap(viewModel.archiveAccessFailure?.recoveryMessage)
        XCTAssertTrue(recoveryMessage.hasPrefix("Niko Music Hub could not open “Fixture Archive”."))
        XCTAssertTrue(recoveryMessage.contains("Grant access again to scan this folder."))
        XCTAssertTrue(recoveryMessage.contains("Songs already in the catalog stay on disk; they are hidden until access is restored."))
        XCTAssertEqual(
            viewModel.persistenceWarningMessage,
            "Archive root access could not be restored: Fixture Archive."
        )
        XCTAssertFalse(viewModel.retryStoredArchiveAccess())
        XCTAssertTrue(viewModel.showsArchiveAccessRecovery)
        XCTAssertEqual(viewModel.storedArchiveAccessDirectory()?.path, fixture.nonMusicVaultPath)
    }

    func testCompletedOnboardingWithoutStoredRootIsEmptyLibraryNotRecovery() throws {
        let fixture = try IsolatedArchiveSettingsFixture()
        defer { fixture.tearDown() }

        try fixture.store.updateSettings { settings in
            settings.musicRoots = []
            settings.archiveOnboardingCompleted = true
        }

        let viewModel = fixture.makeViewModel()

        XCTAssertTrue(viewModel.roots.isEmpty)
        XCTAssertTrue(viewModel.songs.isEmpty)
        XCTAssertFalse(viewModel.needsFirstRunOnboarding)
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertFalse(viewModel.showsArchiveAccessRecovery)
    }

    func testFirstRunRemainsWhenNoStoredRoot() throws {
        let fixture = try IsolatedArchiveSettingsFixture()
        defer { fixture.tearDown() }

        let viewModel = fixture.makeViewModel()
        XCTAssertTrue(viewModel.roots.isEmpty)
        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertFalse(viewModel.showsArchiveAccessRecovery)
        XCTAssertTrue(viewModel.needsFirstRunOnboarding)
    }

    func testChooseFolderClearsAccessFailureAndLeavesRecoveryPath() throws {
        let fixture = try IsolatedArchiveSettingsFixture()
        defer { fixture.tearDown() }

        let stored = StoredMusicRoot(
            id: UUID(),
            role: .scanOnly,
            displayName: "Fixture Archive",
            pathFallback: fixture.nonMusicVaultPath,
            securityScopedBookmark: Data([0x00, 0x01, 0x02])
        )
        try fixture.store.updateSettings { settings in
            settings.musicRoots = [stored]
            settings.archiveOnboardingCompleted = true
        }

        let restoredRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-004-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: restoredRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: restoredRoot) }

        let viewModel = fixture.makeViewModel()
        XCTAssertTrue(viewModel.showsArchiveAccessRecovery)

        viewModel.addRoot(restoredRoot)

        XCTAssertNil(viewModel.archiveAccessFailure)
        XCTAssertFalse(viewModel.showsArchiveAccessRecovery)
        XCTAssertFalse(viewModel.needsFirstRunOnboarding)
        XCTAssertEqual(viewModel.roots.map(\.path), [restoredRoot.standardizedFileURL.path])
    }

    func testUserFacingReasonForStaleAndMissingBookmarks() {
        XCTAssertEqual(
            ArchiveBrowserViewModel.userFacingArchiveAccessReason(from: SecurityScopedBookmarkError.staleBookmark),
            "Saved folder access is out of date."
        )
        XCTAssertEqual(
            ArchiveBrowserViewModel.userFacingArchiveAccessReason(from: SecurityScopedBookmarkError.missingBookmark),
            "Saved folder access is missing."
        )
    }

    func testRecoveryOverlayIsWiredInsteadOfEmptyBoard() throws {
        let browser = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift",
            encoding: .utf8
        )
        let recovery = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveAccessRecoveryView.swift",
            encoding: .utf8
        )
        let board = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBoardView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(browser.contains("showsArchiveAccessRecovery"))
        XCTAssertTrue(browser.contains("ArchiveAccessRecoveryView"))
        XCTAssertTrue(browser.contains("grantArchiveAccess"))
        XCTAssertTrue(recovery.contains("Archive access needs attention"))
        XCTAssertTrue(recovery.contains("Choose Folder"))
        XCTAssertTrue(recovery.contains("Grant Access"))
        XCTAssertFalse(recovery.contains("No songs yet"))
        XCTAssertTrue(board.contains("showsArchiveAccessRecovery"))
        XCTAssertTrue(board.contains("EmptyView()"))
        let emptyBoardIndex = try XCTUnwrap(board.range(of: "No songs yet"))
        let recoveryGateIndex = try XCTUnwrap(board.range(of: "showsArchiveAccessRecovery"))
        XCTAssertTrue(recoveryGateIndex.lowerBound < emptyBoardIndex.lowerBound)
    }
}

private struct IsolatedArchiveSettingsFixture {
    let suiteName: String
    let store: UserDefaultsSettingsStore
    let runtime: MusicHubRuntimeEnvironment
    let nonMusicVaultPath: String
    private let userDefaults: UserDefaults

    init() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        suiteName = "FeatureArchiveBrowserTests.NMH004.\(UUID())"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.settingsSuiteKey: suiteName,
        ])
        nonMusicVaultPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-004-not-a-music-vault-\(UUID().uuidString)", isDirectory: true)
            .path
    }

    @MainActor
    func makeViewModel() -> ArchiveBrowserViewModel {
        ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: runtime,
            scanOverride: { _ in ScanResult() }
        )
    }

    func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}
