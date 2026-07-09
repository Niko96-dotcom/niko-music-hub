import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveBrowserViewModelTests: XCTestCase {
    func testPersistsAddedArchiveRoot() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubPersistedRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make(settingsStore: store))
        viewModel.roots = []
        viewModel.addRoot(root)

        let reloaded = ArchiveBrowserViewModel(context: TestToolContext.make(settingsStore: store))
        XCTAssertEqual(reloaded.roots.map(\.path), [root.standardizedFileURL.path])
    }

    func testFilesystemWatcherStartupFailureSurfacesStatusMessage() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubWatcherFail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: FailingArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: [], globalWarnings: [], skippedEntries: []) }
        )
        viewModel.roots = [root]
        viewModel.restartArchiveRootWatching()

        XCTAssertEqual(
            viewModel.statusMessage,
            "Archive filesystem watcher unavailable — use Rescan to refresh after external edits."
        )
    }

    func testPersistsMultipleArchiveRoots() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        let firstRoot = buildDir.appendingPathComponent("NikoMusicHubMultiRootA-\(UUID().uuidString)", isDirectory: true)
        let secondRoot = buildDir.appendingPathComponent("NikoMusicHubMultiRootB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make(settingsStore: store))
        viewModel.roots = []
        viewModel.addRoots([firstRoot, secondRoot])

        let reloaded = ArchiveBrowserViewModel(context: TestToolContext.make(settingsStore: store))
        XCTAssertEqual(
            reloaded.roots.map(\.path),
            [firstRoot.standardizedFileURL.path, secondRoot.standardizedFileURL.path]
        )
    }

    func testAddRootsIgnoresDuplicates() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubDuplicateRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        viewModel.roots = []
        viewModel.addRoots([root, root])
        XCTAssertEqual(viewModel.roots.map(\.path), [root.standardizedFileURL.path])
    }

    func testAddingRootStartsScan() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make(settingsStore: store))
        viewModel.roots = []

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubAutoScan-\(UUID().uuidString)", isDirectory: true)
        let songFolder = root.appendingPathComponent("Auto Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("Auto Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        viewModel.addRoot(root)
        let deadline = Date().addingTimeInterval(2)
        while viewModel.songs.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.songs.map(\.displayTitle), ["Auto Song"])
        XCTAssertTrue(viewModel.statusMessage?.contains("1 songs") == true)
    }

    func testDefaultBrowseOrderPutsNewestCPRFirst() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubRecentCPRDefault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let oldCPR = ProjectVersion(
            filePath: root.appendingPathComponent("Alpha/Alpha.cpr"),
            fileName: "Alpha.cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newCPR = ProjectVersion(
            filePath: root.appendingPathComponent("Zulu/Zulu.cpr"),
            fileName: "Zulu.cpr",
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let alpha = Song(
            folderPath: root.appendingPathComponent("Alpha", isDirectory: true),
            originalFolderName: "Alpha",
            displayTitle: "Alpha",
            projectVersions: [oldCPR],
            latestCPR: oldCPR
        )
        let zulu = Song(
            folderPath: root.appendingPathComponent("Zulu", isDirectory: true),
            originalFolderName: "Zulu",
            displayTitle: "Zulu",
            projectVersions: [newCPR],
            latestCPR: newCPR
        )
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in
                ScanResult(songs: [alpha, zulu], globalWarnings: [], skippedEntries: [])
            }
        )
        viewModel.roots = [root]

        await viewModel.scan()

        XCTAssertEqual(viewModel.sortMode, .recentCPR)
        XCTAssertEqual(viewModel.filteredSongs.map(\.displayTitle), ["Zulu", "Alpha"])
    }

    func testDevArchiveRootEnvBootstrapsWithoutPersistingOrCompletingOnboarding() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let devRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubDevArchiveRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: devRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: devRoot)
            unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        }

        setenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT", devRoot.path, 1)
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make(settingsStore: store))

        XCTAssertEqual(viewModel.roots.map(\.path), [devRoot.standardizedFileURL.path])
        XCTAssertTrue(try store.loadSettings().archiveRoots.isEmpty)
        XCTAssertFalse(try store.loadSettings().archiveOnboardingCompleted)
    }

    func testNormalLaunchKeepsSavedRootsEvenWhenCurrentlyUnavailable() async throws {
        try CubaseFixtures.ensureGenerated()
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let publicRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubPublicRootTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: publicRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: publicRoot) }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-music-hub-temp-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try store.saveSettings(AppSettings(
            archiveRoots: [
                StoredArchiveRoot(path: publicRoot.path),
                StoredArchiveRoot(path: CubaseFixtures.archiveRoot.path),
                StoredArchiveRoot(path: tempRoot.path),
                StoredArchiveRoot(path: "/var/folders/niko-music-hub-invalid-root"),
                StoredArchiveRoot(path: "/tmp/niko-music-hub-missing-root")
            ]
        ))

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store)
        )

        XCTAssertEqual(
            viewModel.roots.map(\.path),
            [
                publicRoot.standardizedFileURL.path,
                CubaseFixtures.archiveRoot.standardizedFileURL.path,
                tempRoot.standardizedFileURL.path,
                "/var/folders/niko-music-hub-invalid-root",
                "/tmp/niko-music-hub-missing-root"
            ]
        )
        XCTAssertEqual(
            try store.loadSettings().archiveRoots.map(\.path),
            [
                publicRoot.path,
                CubaseFixtures.archiveRoot.path,
                tempRoot.path,
                "/var/folders/niko-music-hub-invalid-root",
                "/tmp/niko-music-hub-missing-root"
            ]
        )
    }

    func testScanFixtureRootFindsNeonHook() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let context = TestToolContext.make()

        let viewModel = ArchiveBrowserViewModel(context: context)
        await viewModel.scan()
        XCTAssertFalse(viewModel.songs.isEmpty)
        viewModel.setSearchQuery("Neon Hook", immediate: true)
        XCTAssertEqual(viewModel.filteredSongs.count, 1)
        XCTAssertEqual(viewModel.filteredSongs.first?.displayTitle, "Neon Hook")
        let songID = try XCTUnwrap(viewModel.filteredSongs.first?.id)
        XCTAssertFalse(viewModel.searchMatchSummaries[songID, default: ""].isEmpty)
    }

    func testDebouncedSearchQueryRecomputesFilteredSongs() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            browseSearchDebounceNanoseconds: 50_000_000
        )
        await viewModel.scan()
        let fullCount = viewModel.filteredSongs.count
        XCTAssertGreaterThan(fullCount, 1)

        viewModel.setSearchQuery("Neon Hook", immediate: false)
        XCTAssertEqual(viewModel.searchQuery, "Neon Hook")
        XCTAssertEqual(viewModel.filteredSongs.count, fullCount)

        let deadline = Date().addingTimeInterval(2)
        while viewModel.filteredSongs.count != 1, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.filteredSongs.count, 1)
        XCTAssertEqual(viewModel.filteredSongs.first?.displayTitle, "Neon Hook")
    }

    func testSearchFindsSkippedRootLabel() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.setSearchQuery("LOOSE_FILE.txt", immediate: true)

        XCTAssertEqual(viewModel.skippedSearchMatches.first?.entry.label, "LOOSE_FILE.txt")
        XCTAssertTrue(viewModel.skippedSearchMatches.first?.matchSummary.contains("skipped label") == true)
    }

    func testScanExposesDiagnosticsSummary() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()

        let diagnostics = try XCTUnwrap(viewModel.scanDiagnostics)
        XCTAssertEqual(diagnostics.songCount, 9)
        XCTAssertEqual(diagnostics.songsWithWarningsCount, 1)
        XCTAssertTrue(
            diagnostics.skippedEntries.contains { $0.kind == .nonFolderAtRoot }
        )
        XCTAssertFalse(diagnostics.summaryLine.isEmpty)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let panel = ArchiveDiagnosticsPanelContext.from(diagnostics, homeDirectory: home)
        XCTAssertEqual(panel.supportSummaryLine, diagnostics.exportSummaryLine(homeDirectory: home))
        XCTAssertEqual(panel.rootHealthBadge, "1 song warning · 2 skipped at roots")
        XCTAssertTrue(panel.supportSummaryLine.contains("Scanned 9 songs"))
        XCTAssertFalse(diagnostics.displayRootPaths().isEmpty)
        XCTAssertTrue(
            diagnostics.displayRootPaths().first?.contains("CubaseArchive") == true
                || diagnostics.displayRootPaths().first?.hasPrefix("~") == true
        )
    }

    func testPerformExportSurfacesFailureOnStatusMessage() {
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        struct SampleError: LocalizedError {
            var errorDescription: String? { "sample failure" }
        }
        viewModel.performExport { throw SampleError() }
        XCTAssertEqual(viewModel.statusMessage, "Export failed: sample failure")
    }

    func testBrowseFilterSidebarUIMetadata() {
        XCTAssertEqual(
            ArchiveBrowseFilter.sidebarFilters,
            [.hasStems, .noPreview, .hasWarnings]
        )
        XCTAssertEqual(ArchiveBrowseFilter.hasStems.sidebarSymbolName, "waveform.path")
        XCTAssertEqual(
            ArchiveBrowseFilter.noPreview.sidebarAccessibilityLabel,
            "Songs missing a preview"
        )
    }

    func testClearScanResultsEmptiesFilteredSongs() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        XCTAssertFalse(viewModel.filteredSongs.isEmpty)

        viewModel.clearScanResults()
        XCTAssertTrue(viewModel.songs.isEmpty)
        XCTAssertTrue(viewModel.filteredSongs.isEmpty)
        XCTAssertNil(viewModel.selectedSong)
    }

    func testRemoveRootClearsRootBoundArchiveState() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        let selected = try XCTUnwrap(viewModel.songs.first)
        viewModel.selectSong(selected)
        viewModel.setSearchQuery(selected.effectiveDisplayTitle, immediate: true)
        viewModel.toggleBrowseFilter(.hasWarnings)
        // Selection may clear when the song leaves the filtered list — that is intentional.
        viewModel.selectShelf(.recentlyBounced)
        viewModel.refreshIntelligenceNow()

        XCTAssertFalse(viewModel.songs.isEmpty)
        XCTAssertNotNil(viewModel.scanDiagnostics)
        XCTAssertFalse(viewModel.searchQuery.isEmpty)

        viewModel.removeRoot(CubaseFixtures.archiveRoot)

        XCTAssertTrue(viewModel.roots.isEmpty)
        XCTAssertTrue(viewModel.songs.isEmpty)
        XCTAssertTrue(viewModel.filteredSongs.isEmpty)
        XCTAssertTrue(viewModel.searchMatchSummaries.isEmpty)
        XCTAssertTrue(viewModel.skippedSearchMatches.isEmpty)
        XCTAssertNil(viewModel.selectedSong)
        XCTAssertNil(viewModel.scanDiagnostics)
        XCTAssertNil(viewModel.statusMessage)
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertEqual(viewModel.selectedShelf, .allSongs)
        XCTAssertTrue(viewModel.browseFilter.isEmpty)
        XCTAssertTrue(viewModel.pendingCollaboratorSuggestions.isEmpty)
        XCTAssertTrue(viewModel.duplicateSongHints.isEmpty)
        XCTAssertNil(viewModel.missingAudioReport)
    }

    func testRemoveOneRootClearsCatalogAndPersistsRemainingRoot() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        let firstRoot = buildDir.appendingPathComponent("NikoMusicHubRemoveRootA-\(UUID().uuidString)", isDirectory: true)
        let secondRoot = buildDir.appendingPathComponent("NikoMusicHubRemoveRootB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = [firstRoot, secondRoot]
        viewModel.clearScanResults()

        viewModel.removeRoot(firstRoot)

        XCTAssertEqual(viewModel.roots.map(\.path), [secondRoot.standardizedFileURL.path])
        XCTAssertTrue(viewModel.songs.isEmpty)
        XCTAssertTrue(viewModel.filteredSongs.isEmpty)
        XCTAssertEqual(viewModel.statusMessage, "Archive roots changed. Scan to refresh.")
        XCTAssertEqual(
            try settingsStore.loadSettings().archiveRoots.map(\.path),
            [secondRoot.standardizedFileURL.path]
        )
    }

    func testStaleScanResultIsIgnoredAfterRootRemoval() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-scan-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let indexStore = RecordingArchiveIndexStore()
        var continuation: CheckedContinuation<ScanResult, Error>?
        let staleSong = Song(
            folderPath: root.appendingPathComponent("Stale Song", isDirectory: true),
            originalFolderName: "Stale Song",
            displayTitle: "Stale Song"
        )
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveIndexStore: indexStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in
                try await withCheckedThrowingContinuation { pending in
                    continuation = pending
                }
            }
        )
        viewModel.roots = [root]

        let scanTask = Task { await viewModel.scan() }
        let deadline = Date().addingTimeInterval(2)
        while continuation == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(continuation)

        viewModel.removeRoot(root)
        continuation?.resume(returning: ScanResult(songs: [staleSong], globalWarnings: [], skippedEntries: []))
        await scanTask.value

        XCTAssertTrue(viewModel.songs.isEmpty)
        XCTAssertTrue(viewModel.filteredSongs.isEmpty)
        XCTAssertNil(viewModel.scanDiagnostics)
        XCTAssertEqual(indexStore.savedSnapshots.count, 0)
    }

    func testArchiveRootPersistenceFailureIsVisible() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("root-save-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsStore = ThrowingSettingsStore(throwOnUpdate: true)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: [], globalWarnings: [], skippedEntries: []) }
        )

        viewModel.addRoot(root)

        XCTAssertEqual(viewModel.roots.map(\.path), [root.standardizedFileURL.path])
        XCTAssertTrue(viewModel.statusMessage?.contains("Archive settings could not be saved") == true)
    }

    func testArchiveCacheLoadFailureIsVisibleOnLaunch() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubCacheLoadRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try settingsStore.saveSettings(AppSettings(archiveRoots: [StoredArchiveRoot(path: root.path)]))

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveIndexStore: ThrowingArchiveIndexStore(throwOnLoad: true)
        )

        XCTAssertEqual(viewModel.roots.map(\.path), [root.standardizedFileURL.path])
        XCTAssertTrue(viewModel.statusMessage?.contains("Archive cache could not be loaded") == true)
    }

    func testLaunchWithCachedIndexRefreshesFromDisk() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubCachedRefresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try settingsStore.saveSettings(AppSettings(archiveRoots: [StoredArchiveRoot(path: root.path)]))

        let stale = Song(
            folderPath: root.appendingPathComponent("Stale Bounce", isDirectory: true),
            originalFolderName: "Stale Bounce",
            displayTitle: "Stale Bounce"
        )
        let fresh = Song(
            folderPath: root.appendingPathComponent("Fresh Demo", isDirectory: true),
            originalFolderName: "Fresh Demo",
            displayTitle: "Fresh Demo"
        )
        let indexStore = RecordingArchiveIndexStore(
            loadSnapshot: ArchiveIndexSnapshot(
                roots: [root.path],
                songs: [stale],
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveIndexStore: indexStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in
                ScanResult(songs: [fresh], globalWarnings: [], skippedEntries: [])
            }
        )

        let deadline = Date().addingTimeInterval(2)
        while viewModel.songs.first?.displayTitle != "Fresh Demo", Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.songs.map(\.displayTitle), ["Fresh Demo"])
        XCTAssertEqual(indexStore.savedSnapshots.last?.songs.map(\.displayTitle), ["Fresh Demo"])
    }

    func testArchiveCacheSaveFailureIsVisibleAfterSuccessfulScan() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-save-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let song = Song(
            folderPath: root.appendingPathComponent("Cache Song", isDirectory: true),
            originalFolderName: "Cache Song",
            displayTitle: "Cache Song"
        )
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveIndexStore: ThrowingArchiveIndexStore(throwOnSave: true),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: [song], globalWarnings: [], skippedEntries: []) }
        )
        viewModel.roots = [root]

        await viewModel.scan()

        XCTAssertEqual(viewModel.songs.map(\.displayTitle), ["Cache Song"])
        XCTAssertTrue(viewModel.statusMessage?.contains("Archive cache could not be saved") == true)
    }

    func testMetadataSaveFailureIsVisibleWithoutDiscardingEdit() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }
        let metadataStore = ThrowingSongUserMetadataStore(throwOnSave: true)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Neon Hook" })

        viewModel.updateVirtualTitle(for: song, title: "Visible Edit")

        let edited = try XCTUnwrap(viewModel.songs.first { $0.id == song.id })
        XCTAssertEqual(edited.effectiveDisplayTitle, "Visible Edit")
        XCTAssertTrue(viewModel.statusMessage?.contains("Song metadata could not be saved") == true)
    }

    func testArchivePersistenceSourceDoesNotSwallowRootSettingsWrites() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel.swift",
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("try? settingsStore.updateSettings"))
    }

    func testSelectShelfByCollaboratorDefaultsCollaboratorAndFilters() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-shelf-vm-\(UUID().uuidString).sqlite")
        let collaboratorStore = try SQLiteCollaboratorStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            collaboratorStore: collaboratorStore
        )
        let collaborator = try XCTUnwrap(viewModel.upsertCollaborator(name: "Shelf Default"))
        await viewModel.scan()
        let neon = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Neon Hook" })
        viewModel.assignCollaborators(to: neon, collaboratorIDs: [collaborator.id])

        viewModel.selectShelf(.byCollaborator)
        XCTAssertEqual(viewModel.selectedCollaboratorID, collaborator.id)
        XCTAssertEqual(viewModel.filteredSongs.count, 1)
        XCTAssertEqual(viewModel.filteredSongs.first?.id, neon.id)
    }

    func testChangingCollaboratorRefiltersBrowse() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-collab-change-vm-\(UUID().uuidString).sqlite")
        let collaboratorStore = try SQLiteCollaboratorStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            collaboratorStore: collaboratorStore
        )
        let collabA = try XCTUnwrap(viewModel.upsertCollaborator(name: "Collab A"))
        let collabB = try XCTUnwrap(viewModel.upsertCollaborator(name: "Collab B"))
        await viewModel.scan()
        let neon = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Neon Hook" })
        let lab = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        viewModel.assignCollaborators(to: neon, collaboratorIDs: [collabA.id])
        viewModel.assignCollaborators(to: lab, collaboratorIDs: [collabB.id])

        viewModel.selectShelf(.byCollaborator)
        viewModel.setSelectedCollaboratorID(collabA.id)
        XCTAssertEqual(viewModel.filteredSongs.map(\.id), [neon.id])

        viewModel.setSelectedCollaboratorID(collabB.id)
        XCTAssertEqual(viewModel.filteredSongs.map(\.id), [lab.id])
    }

    func testToggleBrowseFilterReassignsOptionSetForPublishedUpdates() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        let baselineCount = viewModel.filteredSongs.count

        XCTAssertFalse(viewModel.browseFilter.contains(.hasWarnings))
        viewModel.toggleBrowseFilter(.hasWarnings)
        XCTAssertTrue(viewModel.browseFilter.contains(.hasWarnings))
        XCTAssertLessThan(viewModel.filteredSongs.count, baselineCount)

        viewModel.toggleBrowseFilter(.hasWarnings)
        XCTAssertFalse(viewModel.browseFilter.contains(.hasWarnings))
        XCTAssertEqual(viewModel.filteredSongs.count, baselineCount)
    }

    func testBrokenFolderExposesDisplaySidecarNotes() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()

        let broken = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Broken Folder Example" })
        XCTAssertEqual(broken.displaySidecarNotes(), "notes only")

        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        XCTAssertNil(neon.displaySidecarNotes())
    }

    func testScanExposesPreviewRankingSummaryForLab() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()

        let lab = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        let summary = try XCTUnwrap(PreviewRankingExplainability.mainPreviewSummary(for: lab))
        XCTAssertTrue(summary.contains("v3"))
        XCTAssertTrue(summary.contains("wav"))
    }

    func testExportDiagnosticsIncludesSelectedSongPreviewRanking() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        let lab = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        viewModel.selectSong(lab)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("selected_song_title=Lab Song"))
        XCTAssertTrue(text.contains("selected_song_cpr=1 version"))
        XCTAssertTrue(text.contains("main_preview_summary="))
        XCTAssertTrue(text.contains("v3"))
        XCTAssertTrue(text.contains("preview_rank_line="))
        XCTAssertTrue(text.contains("preview_ranking_tiebreak_legend="))
        XCTAssertTrue(text.contains("too_short_non_main="))
        XCTAssertTrue(text.contains("songs_with_too_short="))
        XCTAssertTrue(
            text.contains(
                "too_short_song=Lab Song count=1 clips=Lab Song short clip.wav"
            )
        )
        XCTAssertTrue(text.contains("preview_ranking_scan_callout="))
        XCTAssertTrue(text.contains("preview_ranking_selected_header="))
    }

    func testExportDiagnosticsIncludesSelectedSongCPRAndWarnings() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()

        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        viewModel.selectSong(neon)
        try viewModel.exportDiagnostics()
        let neonPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let neonText = try String(contentsOf: URL(fileURLWithPath: neonPath), encoding: .utf8)
        XCTAssertTrue(neonText.contains("selected_song_cpr=2 versions"))
        XCTAssertTrue(neonText.contains("latest Neon Hook.cpr"))
        XCTAssertFalse(neonText.contains("selected_song_warning="))

        let broken = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Broken Folder Example" })
        viewModel.selectSong(broken)
        try viewModel.exportDiagnostics()
        let brokenPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let brokenText = try String(contentsOf: URL(fileURLWithPath: brokenPath), encoding: .utf8)
        XCTAssertTrue(brokenText.contains("selected_song_title=Broken Folder Example"))
        XCTAssertTrue(brokenText.contains("selected_song_cpr=no CPR versions"))
        XCTAssertTrue(brokenText.contains("selected_song_warning=No CPR project files found"))
        XCTAssertTrue(brokenText.contains("selected_song_notes=notes only"))
    }

    func testSelectSongCollapsesDetailsForCalmFirstViewport() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first)
        let second = try XCTUnwrap(viewModel.songs.dropFirst().first)

        viewModel.selectSong(first)
        viewModel.songDetailsExpanded = true
        viewModel.pluginsSectionExpanded = true

        viewModel.selectSong(second)
        XCTAssertEqual(viewModel.selectedSong?.id, second.id)
        XCTAssertFalse(viewModel.songDetailsExpanded)
        XCTAssertFalse(viewModel.pluginsSectionExpanded)
    }

    func testSearchClearsSelectionWhenSongLeavesFilteredList() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            browseSearchDebounceNanoseconds: 0
        )
        await viewModel.scan()
        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        viewModel.selectSong(neon)
        XCTAssertEqual(viewModel.selectedSong?.id, neon.id)

        viewModel.setSearchQuery("zzzz-no-match", immediate: true)
        XCTAssertNil(viewModel.selectedSong)
    }

    func testScanRefreshUpdatesSelectedSongSnapshot() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        viewModel.selectSong(neon)

        // Simulate a catalog refresh that replaces the song struct while keeping the id.
        var refreshed = neon
        refreshed.appNote = "post-scan note"
        viewModel.applyCatalogScanUpdate(
            ArchiveCatalogCoordinator.CatalogScanApplyResult(
                songs: viewModel.songs.map { $0.id == neon.id ? refreshed : $0 },
                diagnostics: try XCTUnwrap(viewModel.scanDiagnostics),
                statusMessage: "refreshed",
                scannedAt: Date(),
                shouldPersistUserMetadata: false
            ),
            roots: viewModel.roots
        )
        XCTAssertEqual(viewModel.selectedSong?.id, neon.id)
        XCTAssertEqual(viewModel.selectedSong?.appNote, "post-scan note")
    }

    func testExportDiagnosticsIncludesSkippedSearchContext() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.setSearchQuery("LOOSE_FILE.txt", immediate: true)
        XCTAssertEqual(viewModel.skippedSearchMatches.count, 1)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("skipped_search_query=LOOSE_FILE.txt"))
        XCTAssertTrue(text.contains("skipped_search_match label=LOOSE_FILE.txt"))
        XCTAssertTrue(text.contains("summary="))
        XCTAssertTrue(text.contains("skipped label"))
    }

    func testExportDiagnosticsIncludesWarningSearchContext() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.setSearchQuery("project", immediate: true)
        XCTAssertEqual(viewModel.filteredSongs.count, 1)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("search_query=project"))
        XCTAssertTrue(text.contains("search_match title=Broken Folder Example"))
        XCTAssertTrue(text.contains("scan warning"))
    }

    func testExportDiagnosticsIncludesNotesSearchContext() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.setSearchQuery("nts nly", immediate: true)
        XCTAssertEqual(viewModel.filteredSongs.count, 1)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("search_query=nts nly"))
        XCTAssertTrue(text.contains("search_match title=Broken Folder Example"))
        XCTAssertTrue(text.contains("fuzzy song note"))
    }

    func testExportDiagnosticsIncludesActiveSearchContext() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.setSearchQuery("neon hk", immediate: true)
        XCTAssertEqual(viewModel.filteredSongs.count, 1)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("search_query=neon hk"))
        XCTAssertTrue(text.contains("search_match title=Neon Hook"))
        XCTAssertTrue(text.contains("summary="))
    }

    func testLoadsCachedIndexWhenRootsMatch() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        let root = buildDir.appendingPathComponent("NikoMusicHubCacheRoot-\(UUID().uuidString)", isDirectory: true)
        let songFolder = root.appendingPathComponent("Cached Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("Cached Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-index-\(UUID().uuidString).sqlite")
        let indexStore = try SQLiteArchiveIndexStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let song = Song(
            folderPath: root.appendingPathComponent("Cached Song", isDirectory: true),
            originalFolderName: "Cached Song",
            displayTitle: "Cached Song"
        )
        try indexStore.save(
            ArchiveIndexSnapshot(
                roots: [root.path],
                songs: [song],
                scannedAt: Date()
            )
        )
        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: root.path)]
        }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveIndexStore: indexStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        let deadline = Date().addingTimeInterval(2)
        while viewModel.statusMessage?.contains("1 songs") != true, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.songs.count, 1)
        XCTAssertEqual(viewModel.songs.first?.displayTitle, "Cached Song")
        XCTAssertTrue(viewModel.statusMessage?.contains("1 songs") == true)
    }

    func testLaunchWithSavedRootAndNoCacheStartsScan() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubLaunchScan-\(UUID().uuidString)", isDirectory: true)
        let songFolder = root.appendingPathComponent("Launch Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("Launch Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: root.path)]
            settings.archiveOnboardingCompleted = true
        }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        let deadline = Date().addingTimeInterval(2)
        while viewModel.songs.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.songs.map(\.displayTitle), ["Launch Song"])
    }

    func testFirstRunOnboardingWhenRootsEmpty() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make(settingsStore: store))
        viewModel.roots = []
        viewModel.refreshFirstRunState()
        XCTAssertTrue(viewModel.needsFirstRunOnboarding)

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubOnboarding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        viewModel.addRoot(root)
        XCTAssertFalse(viewModel.needsFirstRunOnboarding)
        XCTAssertTrue(try store.loadSettings().archiveOnboardingCompleted)
    }

    func testVirtualTitlePersistsAndSearchMatchesAlias() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-metadata-vm-\(UUID().uuidString).sqlite")
        let indexStore = try SQLiteArchiveIndexStore(databaseURL: databaseURL)
        let metadataStore = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveIndexStore: indexStore,
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        await viewModel.scan()
        let neon = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Neon Hook" })
        viewModel.updateVirtualTitle(for: neon, title: "Electric Neon")
        viewModel.updateAliases(for: neon, aliasesText: "glowstick")
        viewModel.updateWorkflowStatus(for: neon, status: .waitingFeedback)
        let afterUpdate = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Neon Hook" })
        XCTAssertEqual(afterUpdate.effectiveDisplayTitle, "Electric Neon")
        XCTAssertEqual(afterUpdate.workflowStatus, .waitingFeedback)
        let storedMeta = try metadataStore.loadAll()
        XCTAssertEqual(storedMeta[neon.id]?.virtualTitle, "Electric Neon")
        XCTAssertEqual(storedMeta[neon.id]?.workflowStatus, .waitingFeedback)

        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        let reloaded = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveIndexStore: indexStore,
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        await reloaded.scan()
        let merged = try XCTUnwrap(reloaded.songs.first { $0.originalFolderName == "Neon Hook" })
        XCTAssertEqual(merged.effectiveDisplayTitle, "Electric Neon")
        XCTAssertEqual(merged.aliases, ["glowstick"])
        XCTAssertEqual(merged.workflowStatus, .waitingFeedback)

        reloaded.setSearchQuery("glowstick", immediate: true)
        XCTAssertEqual(reloaded.filteredSongs.count, 1)

        reloaded.setSearchQuery("", immediate: true)
        reloaded.toggleBrowseFilter(.statusWaiting)
        XCTAssertEqual(reloaded.filteredSongs.map(\.id), [merged.id])
    }

    func testManualPreviewSurvivesRescan() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-preview-vm-\(UUID().uuidString).sqlite")
        let metadataStore = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        await viewModel.scan()
        let lab = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        let alternateID = try XCTUnwrap(
            lab.previewCandidates.first { $0.id != lab.mainPreviewCandidateID }
        ).id
        viewModel.setManualMainPreview(for: lab, candidateID: alternateID)
        await viewModel.scan()
        let rescanned = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        XCTAssertEqual(rescanned.mainPreviewCandidateID, alternateID)
        XCTAssertEqual(rescanned.previewSelectionMode, .manual)

        viewModel.revertPreviewToAuto(for: rescanned)
        let auto = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        XCTAssertEqual(auto.previewSelectionMode, .auto)
        XCTAssertNotEqual(auto.mainPreviewCandidateID, alternateID)
    }

    func testCollaboratorAssignmentAndSearch() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-collab-vm-\(UUID().uuidString).sqlite")
        let metadataStore = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        let collaboratorStore = try SQLiteCollaboratorStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            collaboratorStore: collaboratorStore
        )
        let collaborator = try XCTUnwrap(viewModel.upsertCollaborator(name: "Studio Alex"))
        await viewModel.scan()
        let neon = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Neon Hook" })
        viewModel.assignCollaborators(to: neon, collaboratorIDs: [collaborator.id])
        viewModel.selectShelf(.byCollaborator)
        viewModel.setSelectedCollaboratorID(collaborator.id)
        XCTAssertEqual(viewModel.filteredSongs.count, 1)

        viewModel.setSearchQuery("studio", immediate: true)
        XCTAssertEqual(viewModel.filteredSongs.count, 1)
    }

    func testHideSongRemovesFromBrowse() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-hide-vm-\(UUID().uuidString).sqlite")
        let metadataStore = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        await viewModel.scan()
        let before = viewModel.filteredSongs.count
        let target = try XCTUnwrap(viewModel.songs.first)
        viewModel.setSongHidden(target, hidden: true)
        XCTAssertEqual(viewModel.filteredSongs.count, before - 1)
        viewModel.toggleShowHiddenSongs()
        XCTAssertEqual(viewModel.filteredSongs.count, before)
    }

    func testCreateNewSongInTempRoot() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN") }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let draftRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-vm-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: draftRoot) }

        let databaseURL = root.appendingPathComponent("index.sqlite")
        let metadataStore = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = [root]
        let created = try viewModel.createNewSong(
            request: NewSongRequest(name: "CI Song", root: draftRoot, appNote: "test")
        )
        XCTAssertEqual(created.originalFolderName, "CI Song")
        XCTAssertTrue(created.folderPath.path.hasPrefix(draftRoot.path))
        XCTAssertTrue(viewModel.songs.contains(where: { $0.id == created.id }))
    }

    func testCreateNewSongOpensTemplateCPRDryRun() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN") }
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-open-archive-\(UUID().uuidString)", isDirectory: true)
        let draftRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-open-drafts-\(UUID().uuidString)", isDirectory: true)
        let templateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-template-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templateRoot, withIntermediateDirectories: true)
        let templateCPR = templateRoot.appendingPathComponent("Starter.cpr")
        FileManager.default.createFile(atPath: templateCPR.path, contents: Data("fixture".utf8))
        defer {
            try? FileManager.default.removeItem(at: archiveRoot)
            try? FileManager.default.removeItem(at: draftRoot)
            try? FileManager.default.removeItem(at: templateRoot)
        }
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = [archiveRoot]

        let created = try viewModel.createNewSong(
            request: NewSongRequest(name: "Template Song", root: draftRoot, templateFolder: templateRoot)
        )

        XCTAssertEqual(created.effectiveLatestCPR?.fileName, "Starter.cpr")
        XCTAssertTrue(viewModel.lastDryRunLog?.hasSuffix("Template Song/Starter.cpr") == true)
    }

    func testCreateNewSongWithoutCPRExplainsCreatedDraft() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN") }
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-explain-archive-\(UUID().uuidString)", isDirectory: true)
        let draftRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-explain-drafts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: archiveRoot)
            try? FileManager.default.removeItem(at: draftRoot)
        }
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = [archiveRoot]

        let created = try viewModel.createNewSong(
            request: NewSongRequest(name: "No CPR Yet", root: draftRoot)
        )

        XCTAssertNil(created.effectiveLatestCPR)
        XCTAssertNil(viewModel.lastDryRunLog)
        XCTAssertTrue(viewModel.statusMessage?.contains("Created draft No CPR Yet") == true)
        XCTAssertTrue(viewModel.statusMessage?.contains("No CPR project file yet") == true)
    }

    func testCreateNewSongRejectsArchiveRootDestination() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN") }

        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-archive-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archiveRoot) }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = [archiveRoot]

        XCTAssertThrowsError(
            try viewModel.createNewSong(
                request: NewSongRequest(name: "Should Not Write", root: archiveRoot)
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .archiveRootIsReadOnly)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: archiveRoot.appendingPathComponent("Should Not Write", isDirectory: true).path
        ))
    }

    func testSidebarMorePanelSummaryAndVisibility() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = []
        XCTAssertFalse(viewModel.showsSidebarMorePanel)
        XCTAssertEqual(viewModel.sidebarHealthContext.summary, "Health & intelligence")

        viewModel.roots = [
            URL(fileURLWithPath: "/tmp/archive-root", isDirectory: true)
        ]
        XCTAssertTrue(viewModel.showsSidebarMorePanel)
        XCTAssertEqual(viewModel.sidebarHealthContext.summary, "Health & intelligence")
    }

    func testIncrementalFilesystemChangeUpdatesOnlyAffectedSong() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubIncremental-\(UUID().uuidString)", isDirectory: true)
        let songA = root.appendingPathComponent("Song A", isDirectory: true)
        let songB = root.appendingPathComponent("Song B", isDirectory: true)
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: songB, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songA.appendingPathComponent("Song A.cpr").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: songB.appendingPathComponent("Song B.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: root.path)]
            settings.archiveOnboardingCompleted = true
        }

        let watcher = TestArchiveRootWatcher()
        let indexStore = RecordingArchiveIndexStore()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveIndexStore: indexStore,
            archiveRootWatcher: watcher
        )

        await viewModel.scan()
        XCTAssertEqual(Set(viewModel.songs.map(\.displayTitle)), ["Song A", "Song B"])
        XCTAssertTrue(viewModel.songs.allSatisfy { $0.previewCandidates.isEmpty })

        let mixdownFolder = songA.appendingPathComponent("mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdownFolder, withIntermediateDirectories: true)
        let mixdown = mixdownFolder.appendingPathComponent("Song A mix.wav")
        FileManager.default.createFile(atPath: mixdown.path, contents: Data("fixture".utf8))

        watcher.simulateFilesystemChange(paths: [mixdown])

        let deadline = Date().addingTimeInterval(2)
        while viewModel.songs.first(where: { $0.displayTitle == "Song A" })?.previewCandidates.isEmpty != false,
              Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let updatedA = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Song A" })
        let unchangedB = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Song B" })
        XCTAssertEqual(updatedA.previewCandidates.count, 1)
        XCTAssertTrue(unchangedB.previewCandidates.isEmpty)
        XCTAssertEqual(viewModel.songs.count, 2)
        XCTAssertEqual(indexStore.savedSnapshots.count, 2)
    }

    func testIncrementalRescanOnRootLevelCPRPreservesSiblingFolders() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubRootCPR-\(UUID().uuidString)", isDirectory: true)
        let songA = root.appendingPathComponent("Song A", isDirectory: true)
        let songB = root.appendingPathComponent("Song B", isDirectory: true)
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: songB, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songA.appendingPathComponent("Song A.cpr").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: songB.appendingPathComponent("Song B.cpr").path,
            contents: Data("fixture".utf8)
        )
        let looseCPR = root.appendingPathComponent("Loose.cpr")
        FileManager.default.createFile(atPath: looseCPR.path, contents: Data("fixture".utf8))
        defer { try? FileManager.default.removeItem(at: root) }

        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: root.path)]
            settings.archiveOnboardingCompleted = true
        }

        let watcher = TestArchiveRootWatcher()
        let indexStore = RecordingArchiveIndexStore()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveIndexStore: indexStore,
            archiveRootWatcher: watcher
        )

        await viewModel.scan()
        XCTAssertEqual(Set(viewModel.songs.map(\.displayTitle)), ["Song A", "Song B", "Loose"])

        FileManager.default.createFile(atPath: looseCPR.path, contents: Data("updated fixture".utf8))
        watcher.simulateFilesystemChange(paths: [looseCPR])

        let deadline = Date().addingTimeInterval(2)
        while indexStore.savedSnapshots.count < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(Set(viewModel.songs.map(\.displayTitle)), ["Song A", "Song B", "Loose"])
        XCTAssertEqual(indexStore.savedSnapshots.count, 2)
    }

    func testIncrementalRescanAddsNewRootLevelCPR() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubNewRootCPR-\(UUID().uuidString)", isDirectory: true)
        let songA = root.appendingPathComponent("Song A", isDirectory: true)
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songA.appendingPathComponent("Song A.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: root.path)]
            settings.archiveOnboardingCompleted = true
        }

        let watcher = TestArchiveRootWatcher()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: watcher
        )

        await viewModel.scan()
        XCTAssertEqual(Set(viewModel.songs.map(\.displayTitle)), ["Song A"])

        let newLooseCPR = root.appendingPathComponent("Brand New.cpr")
        FileManager.default.createFile(atPath: newLooseCPR.path, contents: Data("fixture".utf8))
        watcher.simulateFilesystemChange(paths: [newLooseCPR])

        let deadline = Date().addingTimeInterval(2)
        while !viewModel.songs.contains(where: { $0.displayTitle == "Brand New" }),
              Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(Set(viewModel.songs.map(\.displayTitle)), ["Song A", "Brand New"])
    }

    func testPendingIncrementalPathsDrainAfterFullScan() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubDrainAfterFull-\(UUID().uuidString)", isDirectory: true)
        let songA = root.appendingPathComponent("Song A", isDirectory: true)
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songA.appendingPathComponent("Song A.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: root.path)]
            settings.archiveOnboardingCompleted = true
        }

        let gate = ScanReleaseGate()
        let watcher = TestArchiveRootWatcher()
        let indexStore = RecordingArchiveIndexStore()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveIndexStore: indexStore,
            archiveRootWatcher: watcher,
            scanOverride: { _ in
                await gate.waitForRelease()
                return ScanResult(songs: [
                    Song(
                        folderPath: songA,
                        originalFolderName: songA.lastPathComponent,
                        displayTitle: "Song A"
                    )
                ])
            }
        )

        let scanningDeadline = Date().addingTimeInterval(2)
        while !viewModel.isScanning, Date() < scanningDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(viewModel.isScanning)

        let mixdownFolder = songA.appendingPathComponent("mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdownFolder, withIntermediateDirectories: true)
        let mixdown = mixdownFolder.appendingPathComponent("Song A mix.wav")
        FileManager.default.createFile(atPath: mixdown.path, contents: Data("fixture".utf8))
        watcher.simulateFilesystemChange(paths: [mixdown])

        gate.release()

        let updateDeadline = Date().addingTimeInterval(3)
        while viewModel.songs.first?.previewCandidates.isEmpty != false, Date() < updateDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.songs.first?.previewCandidates.count, 1)
        XCTAssertEqual(indexStore.savedSnapshots.count, 2)
    }

    func testPendingIncrementalPathsClearedOnRootChange() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let rootA = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubRootChangeA-\(UUID().uuidString)", isDirectory: true)
        let rootB = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubRootChangeB-\(UUID().uuidString)", isDirectory: true)
        let songA = rootA.appendingPathComponent("Song A", isDirectory: true)
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songA.appendingPathComponent("Song A.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: rootA.path)]
            settings.archiveOnboardingCompleted = true
        }

        let watcher = TestArchiveRootWatcher()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: watcher,
            scanOverride: { _ in
                ScanResult(songs: [
                    Song(
                        folderPath: songA,
                        originalFolderName: songA.lastPathComponent,
                        displayTitle: "Song A"
                    )
                ])
            }
        )

        let scanDeadline = Date().addingTimeInterval(2)
        while viewModel.songs.isEmpty, Date() < scanDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let mixdownFolder = songA.appendingPathComponent("mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdownFolder, withIntermediateDirectories: true)
        let mixdown = mixdownFolder.appendingPathComponent("Song A mix.wav")
        FileManager.default.createFile(atPath: mixdown.path, contents: Data("fixture".utf8))
        watcher.simulateFilesystemChange(paths: [mixdown])
        viewModel.roots = [rootB]

        let settleDeadline = Date().addingTimeInterval(2)
        while Date() < settleDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let song = try XCTUnwrap(viewModel.songs.first)
        XCTAssertTrue(song.previewCandidates.isEmpty)
        XCTAssertFalse(viewModel.statusMessage?.contains("filesystem change") ?? false)
    }

    func testExportIndexJSONFromViewModel() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        await viewModel.scan()
        try viewModel.exportIndexJSON()
        let path = try XCTUnwrap(viewModel.lastIndexExportPath)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ArchiveIndexExport.self, from: data)
        XCTAssertGreaterThan(decoded.songCount, 0)
    }

    func testStaleIncrementalRescanDoesNotClearIsScanningDuringFullScan() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        setenv("NIKO_MUSIC_HUB_TEST_INCREMENTAL_HOLD_NS", "300000000", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_TEST_INCREMENTAL_HOLD_NS") }

        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let rootA = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubStaleIncrementalA-\(UUID().uuidString)", isDirectory: true)
        let rootB = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubStaleIncrementalB-\(UUID().uuidString)", isDirectory: true)
        let songA = rootA.appendingPathComponent("Song A", isDirectory: true)
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songA.appendingPathComponent("Song A.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        try settingsStore.updateSettings { settings in
            settings.archiveRoots = [StoredArchiveRoot(path: rootA.path)]
            settings.archiveOnboardingCompleted = true
        }

        let gate = ScanReleaseGate()
        let watcher = TestArchiveRootWatcher()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: watcher,
            scanOverride: { _ in
                await gate.waitForRelease()
                return ScanResult(songs: [
                    Song(
                        folderPath: songA,
                        originalFolderName: songA.lastPathComponent,
                        displayTitle: "Song A"
                    )
                ])
            }
        )

        let initialScanDeadline = Date().addingTimeInterval(2)
        while viewModel.songs.isEmpty, Date() < initialScanDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        gate.release()

        let mixdownFolder = songA.appendingPathComponent("mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdownFolder, withIntermediateDirectories: true)
        let mixdown = mixdownFolder.appendingPathComponent("Song A mix.wav")
        FileManager.default.createFile(atPath: mixdown.path, contents: Data("fixture".utf8))
        watcher.simulateFilesystemChange(paths: [mixdown])

        let incrementalStartDeadline = Date().addingTimeInterval(2)
        while !viewModel.isScanning, Date() < incrementalStartDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        viewModel.roots = [rootB]
        let fullScanTask = Task { await viewModel.scan() }

        let fullScanStartDeadline = Date().addingTimeInterval(2)
        while !viewModel.isScanning, Date() < fullScanStartDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(
            viewModel.isScanning,
            "Stale incremental completion must not clear isScanning while a full scan is active"
        )

        gate.release()
        await fullScanTask.value
    }

    func testRevealInFinderAcceptsSymlinkedArchiveRoot() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("archive-reveal-root-link-\(UUID().uuidString)", isDirectory: true)
        let link = base.appendingPathComponent("archive-link", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createSymbolicLink(at: link, withDestinationURL: CubaseFixtures.archiveRoot)

        let revealed = RevealedURLBox()
        let context = TestToolContext.make(fileActions: CapturingTestFileActions(revealed: revealed))
        let viewModel = ArchiveBrowserViewModel(context: context)
        await viewModel.scan()
        viewModel.roots = [link]

        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        let cpr = try XCTUnwrap(neon.effectiveLatestCPR?.filePath ?? neon.latestCPR?.filePath)
        viewModel.revealInFinder(url: cpr)

        XCTAssertFalse(viewModel.statusMessage?.contains("outside allowed archive roots") ?? false)
        XCTAssertEqual(revealed.urls.count, 1)
        XCTAssertTrue(revealed.urls[0].path.hasSuffix(".cpr"))
    }

    func testRevealInFinderRejectsOutsideAllowedRoots() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()

        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-reveal-outside.txt")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        viewModel.revealInFinder(url: outside)
        XCTAssertEqual(
            viewModel.statusMessage,
            "Path is outside allowed archive roots: \(outside.standardizedFileURL.path)"
        )
    }

    func testCatalogRescanInvalidatesMixdownCacheWhenPreviewModifiedAtChanges() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        guard let previewID = neon.mainPreviewCandidateID else {
            XCTFail("Expected Neon Hook to have a main preview")
            return
        }
        let cacheKey = "\(neon.id)|\(previewID)"
        viewModel.mixdownBPMBySongID[cacheKey] = MixdownBPMEstimate(bpm: 120, confidence: "test")

        var refreshed = neon
        guard let previewIndex = refreshed.previewCandidates.firstIndex(where: { $0.id == previewID }) else {
            XCTFail("Expected preview candidate")
            return
        }
        let preview = refreshed.previewCandidates[previewIndex]
        refreshed.previewCandidates[previewIndex] = PreviewCandidate(
            filePath: preview.filePath,
            fileName: preview.fileName,
            folderRole: preview.folderRole,
            modifiedAt: preview.modifiedAt.addingTimeInterval(60),
            detectedRole: preview.detectedRole,
            detectedVersionNumber: preview.detectedVersionNumber,
            durationSeconds: preview.durationSeconds,
            confidenceScore: preview.confidenceScore,
            confidenceReasons: preview.confidenceReasons
        )

        viewModel.applyCatalogScanUpdate(
            ArchiveCatalogCoordinator.CatalogScanApplyResult(
                songs: viewModel.songs.map { $0.id == neon.id ? refreshed : $0 },
                diagnostics: try XCTUnwrap(viewModel.scanDiagnostics),
                statusMessage: "refreshed preview",
                scannedAt: Date(),
                shouldPersistUserMetadata: false
            ),
            roots: viewModel.roots
        )

        XCTAssertNil(viewModel.mixdownBPMBySongID[cacheKey])
    }

}

private final class ScanReleaseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

private final class RecordingArchiveIndexStore: ArchiveIndexStoring, @unchecked Sendable {
    var loadSnapshot: ArchiveIndexSnapshot?
    private(set) var savedSnapshots: [ArchiveIndexSnapshot] = []

    init(loadSnapshot: ArchiveIndexSnapshot? = nil) {
        self.loadSnapshot = loadSnapshot
    }

    func loadLatest() throws -> ArchiveIndexSnapshot? { loadSnapshot }

    func save(_ snapshot: ArchiveIndexSnapshot) throws {
        savedSnapshots.append(snapshot)
    }

    func clear() throws {}
}

private final class ThrowingArchiveIndexStore: ArchiveIndexStoring, @unchecked Sendable {
    let throwOnLoad: Bool
    let throwOnSave: Bool

    init(throwOnLoad: Bool = false, throwOnSave: Bool = false) {
        self.throwOnLoad = throwOnLoad
        self.throwOnSave = throwOnSave
    }

    func loadLatest() throws -> ArchiveIndexSnapshot? {
        if throwOnLoad { throw TestPersistenceError.forced }
        return nil
    }

    func save(_ snapshot: ArchiveIndexSnapshot) throws {
        if throwOnSave { throw TestPersistenceError.forced }
    }

    func clear() throws {}
}

private final class ThrowingSongUserMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
    let throwOnSave: Bool

    init(throwOnSave: Bool = false) {
        self.throwOnSave = throwOnSave
    }

    func loadAll() throws -> [String: SongUserMetadata] { [:] }

    func upsert(_ metadata: SongUserMetadata) throws {
        if throwOnSave { throw TestPersistenceError.forced }
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        if throwOnSave { throw TestPersistenceError.forced }
    }
}

private final class ThrowingSettingsStore: SettingsStore, @unchecked Sendable {
    private var settings: AppSettings
    private let throwOnUpdate: Bool

    init(settings: AppSettings = .default, throwOnUpdate: Bool = false) {
        self.settings = settings
        self.throwOnUpdate = throwOnUpdate
    }

    func loadSettings() throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        if throwOnUpdate { throw TestPersistenceError.forced }
        self.settings = settings
    }

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        if throwOnUpdate { throw TestPersistenceError.forced }
        update(&settings)
    }
}

private enum TestPersistenceError: LocalizedError {
    case forced

    var errorDescription: String? {
        "forced persistence failure"
    }
}
