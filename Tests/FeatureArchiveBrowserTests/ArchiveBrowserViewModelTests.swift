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

    func testIntelligenceRefreshRetainsOnlyMissingAudioSummary() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubIntelligenceSummary-\(UUID().uuidString)", isDirectory: true)
        let songFolder = root.appendingPathComponent("Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("orphan.wav").path,
            contents: Data("fixture".utf8)
        )
        let song = Song(
            folderPath: songFolder,
            originalFolderName: "Song",
            displayTitle: "Song"
        )
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.songs = [song]

        viewModel.refreshIntelligenceNow()
        let deadline = Date().addingTimeInterval(1)
        while viewModel.missingAudioReport == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let summary = try XCTUnwrap(viewModel.missingAudioReport)
        XCTAssertEqual(summary.noPreview, ["Song"])
        XCTAssertEqual(summary.noCPR, ["Song"])
        XCTAssertTrue(summary.orphanAudioBySongID.isEmpty)
    }

    func testImmediateIntelligenceRefreshCancelsSupersededSnapshot() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let firstSong = Song(
            folderPath: root.appendingPathComponent("First", isDirectory: true),
            originalFolderName: "First",
            displayTitle: "First"
        )
        let secondSong = Song(
            folderPath: root.appendingPathComponent("Second", isDirectory: true),
            originalFolderName: "Second",
            displayTitle: "Second"
        )
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )

        viewModel.songs = [firstSong]
        viewModel.refreshIntelligenceNow()
        viewModel.songs = [secondSong]
        viewModel.refreshIntelligenceNow()

        let deadline = Date().addingTimeInterval(1)
        while viewModel.missingAudioReport == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let summary = try XCTUnwrap(viewModel.missingAudioReport)
        XCTAssertEqual(summary.noPreview, ["Second"])
        XCTAssertEqual(summary.noCPR, ["Second"])
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

    func testRootChangeCancelsActiveFullScanBeforeReplacementApplies() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let firstRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-stale-scan-a-\(UUID().uuidString)", isDirectory: true)
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-stale-scan-b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        let staleScan = CancellationAwareScanGate()
        let replacementSong = Song(
            folderPath: secondRoot.appendingPathComponent("Replacement Song", isDirectory: true),
            originalFolderName: "Replacement Song",
            displayTitle: "Replacement Song"
        )
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { requestedRoots in
                if requestedRoots.standardizedArchivePaths == [firstRoot.standardizedFileURL.path] {
                    return try await staleScan.wait()
                }
                return ScanResult(songs: [replacementSong])
            }
        )
        viewModel.roots = [firstRoot]

        let staleTask = Task { await viewModel.scan() }
        let startDeadline = Date().addingTimeInterval(2)
        while !staleScan.isWaiting, Date() < startDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(staleScan.isWaiting)

        viewModel.roots = [secondRoot]
        let replacementTask = Task { await viewModel.scan() }
        await replacementTask.value

        let cancellationDeadline = Date().addingTimeInterval(2)
        while !staleScan.wasCancelled, Date() < cancellationDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let wasCancelled = staleScan.wasCancelled
        if !wasCancelled {
            staleScan.release()
        }
        await staleTask.value

        XCTAssertTrue(wasCancelled, "Replacing roots must cancel the prior full scan work")
        XCTAssertEqual(viewModel.songs.map(\.displayTitle), ["Replacement Song"])
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

    func testArchiveCacheLoadFailureIsVisibleOnLaunch() async throws {
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
        let deadline = Date().addingTimeInterval(2)
        while viewModel.statusMessage?.contains("Archive cache could not be loaded") != true, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
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
        _ = await viewModel.indexPersistTask?.value

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
        _ = await viewModel.indexPersistTask?.value

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
        XCTAssertTrue(brokenText.contains("selected_song_cpr=no project versions"))
        XCTAssertTrue(brokenText.contains("selected_song_warning=No project files (.cpr or .als) found"))
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
        reloaded.toggleBrowseFilter(.workflowStatus(.waitingFeedback))
        XCTAssertEqual(reloaded.filteredSongs.map(\.id), [merged.id])
    }

    func testMarkingDoneArchivesTheUpdatedWorkflowSnapshot() async throws {
        let runtime = RecordingProjectVaultRuntime()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime
        )
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-done-\(UUID().uuidString)", isDirectory: true)
        let song = Song(
            folderPath: folder,
            originalFolderName: "Workflow Song",
            displayTitle: "Workflow Song"
        )
        viewModel.songs = [song]
        viewModel.filteredSongs = [song]

        viewModel.updateWorkflowStatus(for: song, status: .done)

        var archivedSong: Song?
        for _ in 0..<100 {
            archivedSong = await runtime.lastArchivedSong()
            if archivedSong != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(archivedSong?.workflowStatus, .done)
    }

    func testDoneProjectWithPersistedFailedTransferIsNotAutomaticallyRequeued() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-failed-transfer-\(UUID().uuidString)", isDirectory: true)
        let song = Song(
            folderPath: folder,
            originalFolderName: "Failed Workflow Song",
            displayTitle: "Failed Workflow Song",
            workflowStatus: .done
        )
        let projectID = ProjectID()
        var transfer = VaultTransferRecord(
            projectID: projectID,
            sourceURL: folder,
            stagingURL: folder.appendingPathComponent("staging"),
            destinationURL: folder.appendingPathComponent("generation"),
            state: .failedRecoverable
        )
        transfer.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "provider retry"
        )
        let runtime = RecordingProjectVaultRuntime(snapshots: [
            ProjectVaultRuntimeSnapshot(
                record: ProjectRecord(
                    id: projectID,
                    canonicalTitle: song.effectiveDisplayTitle,
                    locations: [],
                    workflowState: .done
                ),
                transfer: transfer
            ),
        ])
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime
        )
        viewModel.scannedSongs = [song]
        viewModel.songs = [song]
        viewModel.filteredSongs = [song]

        await viewModel.refreshProjectVaultSnapshots()
        try await Task.sleep(for: .milliseconds(100))

        let archiveCallCount = await runtime.archiveCallCount()
        XCTAssertEqual(archiveCallCount, 0)
    }

    func testFailedRecoverablePrimaryActionRetriesThroughRuntime() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let runtime = RecordingProjectVaultRuntime(snapshots: [fixture.snapshot])
        let viewModel = fixture.makeViewModel(runtime: runtime)
        await viewModel.refreshProjectVaultSnapshots()
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.primaryAction, .retry)

        viewModel.performProjectVaultPrimaryAction(for: fixture.song)
        for _ in 0..<100 {
            if await runtime.retryCallCount() > 0,
               !viewModel.projectVaultBusySongIDs.contains(fixture.song.id) { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let retryCallCount = await runtime.retryCallCount()
        XCTAssertEqual(retryCallCount, 1)
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.primaryAction, .openInCubase)
        XCTAssertEqual(viewModel.statusMessage, "Project Vault retry completed and verified.")
    }

    func testRetryBusyStateClearsOnlyAfterRuntimeCompletes() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let gate = ScanReleaseGate()
        let runtime = RecordingProjectVaultRuntime(snapshots: [fixture.snapshot], retryGate: gate)
        let viewModel = fixture.makeViewModel(runtime: runtime)
        await viewModel.refreshProjectVaultSnapshots()

        viewModel.performProjectVaultPrimaryAction(for: fixture.song)
        for _ in 0..<100 where !gate.isWaiting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(gate.isWaiting)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.statusMessage, "Retrying the preserved Project Vault transfer…")

        gate.release()
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.primaryAction, .openInCubase)
    }

    func testRetryRefreshFailureDoesNotClaimVerifiedSuccess() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let runtime = RecordingProjectVaultRuntime(
            snapshots: [fixture.snapshot],
            refreshFailsAfterRetry: true
        )
        let viewModel = fixture.makeViewModel(runtime: runtime)
        await viewModel.refreshProjectVaultSnapshots()

        viewModel.performProjectVaultPrimaryAction(for: fixture.song)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.primaryAction, .openInCubase)
        XCTAssertEqual(
            viewModel.statusMessage,
            "Project Vault retry completed, but the current Vault state could not be refreshed. Review before taking another action."
        )
    }

    func testFailedRetryRefreshesRecoveryRequiredPresentation() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let runtime = RecordingProjectVaultRuntime(
            snapshots: [fixture.snapshot],
            retryFailureState: .recoveryRequired
        )
        let viewModel = fixture.makeViewModel(runtime: runtime)
        await viewModel.refreshProjectVaultSnapshots()

        viewModel.performProjectVaultPrimaryAction(for: fixture.song)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.primaryAction, .review)
        XCTAssertFalse(viewModel.canArchiveInProjectVault(fixture.song))
        XCTAssertTrue(viewModel.statusMessage?.contains("retry stopped safely") == true)
    }

    func testLegacyFinderReviewIsNonmutatingAndRetryUsesSameRestoreIDWithBusyCleared() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let restoreID = UUID()
        let snapshot = try fixture.legacyReviewSnapshot(restoreID: restoreID)
        let gate = ScanReleaseGate()
        let runtime = RecordingProjectVaultRuntime(
            snapshots: [snapshot],
            restoreRetryGate: gate
        )
        let revealed = RevealedURLBox()
        let viewModel = fixture.makeViewModel(
            runtime: runtime,
            fileActions: CapturingTestFileActions(revealed: revealed)
        )
        await viewModel.refreshProjectVaultSnapshots()

        viewModel.performProjectVaultPrimaryAction(for: fixture.song)

        XCTAssertEqual(revealed.urls, [try XCTUnwrap(snapshot.restore?.archiveGenerationURL)])
        let reviewOnlyRetryIDs = await runtime.restoreRetryIDs()
        XCTAssertTrue(reviewOnlyRetryIDs.isEmpty)
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))

        viewModel.retryReviewedProjectVaultRestore(for: fixture.song)
        for _ in 0..<100 where !gate.isWaiting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(gate.isWaiting)
        XCTAssertTrue(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.statusMessage, "Retrying this preserved Project Vault restore…")

        gate.release()
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let completedRetryIDs = await runtime.restoreRetryIDs()
        XCTAssertEqual(completedRetryIDs, [restoreID])
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.statusMessage, "Project Vault restore retry completed and verified.")
    }

    func testLegacyRestoreRetryFailureKeepsReviewAndClearsBusy() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let restoreID = UUID()
        let snapshot = try fixture.legacyReviewSnapshot(restoreID: restoreID)
        let runtime = RecordingProjectVaultRuntime(
            snapshots: [snapshot],
            restoreRetryError: .archiveFailed("forced legacy retry failure")
        )
        let viewModel = fixture.makeViewModel(runtime: runtime)
        await viewModel.refreshProjectVaultSnapshots()

        viewModel.retryReviewedProjectVaultRestore(for: fixture.song)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        let failedRetryIDs = await runtime.restoreRetryIDs()
        XCTAssertEqual(failedRetryIDs, [restoreID])
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.primaryAction, .review)
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.retryRestoreID, restoreID)
        XCTAssertTrue(viewModel.statusMessage?.contains("restore retry stopped safely") == true)
    }

    func testArchiveTransferBindingFailureSnapshotPresentsNonActionableIntegrityReview() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let restoreID = UUID()
        let legacySnapshot = try fixture.legacyReviewSnapshot(restoreID: restoreID)
        var restore = try XCTUnwrap(legacySnapshot.restore)
        restore.failureReason = .archiveTransferBindingUnavailable
        let snapshot = ProjectVaultRuntimeSnapshot(
            record: legacySnapshot.record,
            transfer: legacySnapshot.transfer,
            restore: restore
        )
        let runtime = RecordingProjectVaultRuntime(snapshots: [snapshot])
        let revealed = RevealedURLBox()
        let viewModel = fixture.makeViewModel(
            runtime: runtime,
            fileActions: CapturingTestFileActions(revealed: revealed)
        )

        await viewModel.refreshProjectVaultSnapshots()
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: fixture.song))

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertEqual(
            presentation.explanation,
            "This restore no longer matches its verified archive transfer binding. Existing copies were kept; review archive integrity before continuing."
        )
        XCTAssertFalse(presentation.explanation.contains("Downloading"))
        XCTAssertNil(presentation.reviewAction, "binding failure must not authorize Finder")
        XCTAssertNil(presentation.retryRestoreID, "binding failure must not authorize Retry")
        XCTAssertFalse(viewModel.canArchiveInProjectVault(fixture.song), "owned failed restore must hide Archive")

        viewModel.performProjectVaultPrimaryAction(for: fixture.song)
        viewModel.retryReviewedProjectVaultRestore(for: fixture.song)
        try await Task.sleep(for: .milliseconds(20))

        let retryIDs = await runtime.restoreRetryIDs()
        let archiveCalls = await runtime.archiveCallCount()
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertTrue(retryIDs.isEmpty)
        XCTAssertEqual(archiveCalls, 0)
        XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
    }

    func testActiveDestinationIntegrityMismatchProjectionRetainsTypedBlockerWhenGenerationIsUnbound() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let baseSnapshot = try fixture.legacyReviewSnapshot(restoreID: UUID())
        let transfer = try XCTUnwrap(baseSnapshot.transfer)
        var restore = VaultRestoreRecord(
            projectID: baseSnapshot.record.id,
            archiveGenerationURL: fixture.root.appendingPathComponent(
                "Archive/generations/unbound/generation",
                isDirectory: true
            ),
            stagingURL: fixture.root.appendingPathComponent("Active/.niko-staging/integrity"),
            destinationURL: fixture.song.folderPath,
            manifest: try XCTUnwrap(transfer.manifest),
            archiveTransferID: nil,
            archiveTransferState: transfer.state,
            requiresArchiveMaterialization: false,
            phase: .openingInCubase
        )
        restore.failureReason = .activeDestinationIntegrityMismatch
        restore.error = "Active integrity mismatch"
        let runtime = RecordingProjectVaultRuntime(snapshots: [ProjectVaultRuntimeSnapshot(
            record: baseSnapshot.record,
            transfer: transfer,
            restore: restore
        )])
        let metadataStore = RecordingSongUserMetadataStore()
        let revealed = RevealedURLBox()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(
                settingsStore: fixture.settingsStore,
                fileActions: CapturingTestFileActions(revealed: revealed)
            ),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
            ])
        )
        viewModel.scannedSongs = [fixture.song]
        viewModel.songs = [fixture.song]
        viewModel.filteredSongs = [fixture.song]

        await viewModel.refreshProjectVaultSnapshots()
        let sourceSong = try XCTUnwrap(viewModel.songs.first)
        viewModel.selectSong(sourceSong)
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: sourceSong))

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertEqual(
            presentation.explanation,
            "The restored Active copy no longer matches the verified archive manifest. It will not be opened; existing copies were kept for review."
        )
        XCTAssertFalse(presentation.explanation.contains("every known copy"))
        XCTAssertNil(presentation.reviewAction)
        XCTAssertNil(presentation.retryRestoreID)
        XCTAssertNil(viewModel.preferredRevealURL(for: sourceSong))
        XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: sourceSong))
        XCTAssertFalse(viewModel.canArchiveInProjectVault(sourceSong))

        viewModel.revealInFinder(url: sourceSong.folderPath)
        try? viewModel.openLatestCPR(for: sourceSong)
        viewModel.updateWorkflowStatus(for: sourceSong, status: .done)
        viewModel.archiveInProjectVault(sourceSong)
        viewModel.performProjectVaultPrimaryAction(for: sourceSong)
        viewModel.retryReviewedProjectVaultRestore(for: sourceSong)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(metadataStore.upsertCallCount, 0)
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertNil(viewModel.lastDryRunLog)
        let archiveCalls = await runtime.archiveCallCount()
        let retryCalls = await runtime.retryCallCount()
        let restoreCalls = await runtime.restoreCallCount()
        let restoreRetryIDs = await runtime.restoreRetryIDs()
        XCTAssertEqual(archiveCalls, 0)
        XCTAssertEqual(retryCalls, 0)
        XCTAssertEqual(restoreCalls, 0)
        XCTAssertTrue(restoreRetryIDs.isEmpty)
    }

    func testRestoreOnlyIntegrityMismatchSnapshotBlocksEveryActiveSongAction() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let cprURL = fixture.song.folderPath.appendingPathComponent("Integrity Song.cpr")
        try Data("rejected Active bytes".utf8).write(to: cprURL)
        let cpr = ProjectVersion(
            filePath: cprURL,
            fileName: cprURL.lastPathComponent,
            modifiedAt: Date()
        )
        let activeSong = Song(
            folderPath: fixture.song.folderPath,
            originalFolderName: fixture.song.originalFolderName,
            displayTitle: fixture.song.displayTitle,
            projectVersions: [cpr],
            latestCPR: cpr
        )
        var restore = VaultRestoreRecord(
            projectID: fixture.snapshot.record.id,
            archiveGenerationURL: fixture.root.appendingPathComponent(
                "Unbound/missing-generation",
                isDirectory: true
            ),
            stagingURL: fixture.root.appendingPathComponent("Active/.niko-staging/integrity"),
            destinationURL: activeSong.folderPath,
            manifest: VaultManifest(entries: []),
            archiveTransferID: nil,
            requiresArchiveMaterialization: false,
            phase: .openingInCubase
        )
        restore.failureReason = .activeDestinationIntegrityMismatch
        restore.error = "Active integrity mismatch"
        let runtime = RecordingProjectVaultRuntime(snapshots: [ProjectVaultRuntimeSnapshot(
            record: fixture.snapshot.record,
            transfer: nil,
            restore: restore
        )])
        let metadataStore = RecordingSongUserMetadataStore()
        let revealed = RevealedURLBox()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(
                settingsStore: fixture.settingsStore,
                fileActions: CapturingTestFileActions(revealed: revealed)
            ),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
            ])
        )
        viewModel.scannedSongs = [activeSong]
        viewModel.songs = [activeSong]
        viewModel.filteredSongs = [activeSong]

        await viewModel.refreshProjectVaultSnapshots()
        let sourceSong = try XCTUnwrap(viewModel.songs.first)
        viewModel.selectSong(sourceSong)
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: sourceSong))

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertEqual(
            presentation.explanation,
            "The restored Active copy no longer matches the verified archive manifest. It will not be opened; existing copies were kept for review."
        )
        XCTAssertFalse(presentation.explanation.contains("every known copy"))
        XCTAssertNil(presentation.reviewAction)
        XCTAssertNil(presentation.retryRestoreID)
        XCTAssertNil(viewModel.preferredRevealURL(for: sourceSong))
        XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: sourceSong))
        XCTAssertFalse(viewModel.canArchiveInProjectVault(sourceSong))

        viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: sourceSong))
        viewModel.revealInFinder(url: sourceSong.folderPath)
        try? viewModel.openLatestCPR(for: sourceSong)
        if let selectedSong = viewModel.selectedSong {
            viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: selectedSong))
            try? viewModel.openLatestCPR(for: selectedSong)
        }
        viewModel.updateWorkflowStatus(for: sourceSong, status: .done)
        viewModel.archiveInProjectVault(sourceSong)
        viewModel.performProjectVaultPrimaryAction(for: sourceSong)
        viewModel.retryReviewedProjectVaultRestore(for: sourceSong)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(sourceSong.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        let archiveCalls = await runtime.archiveCallCount()
        let retryCalls = await runtime.retryCallCount()
        let restoreCalls = await runtime.restoreCallCount()
        let restoreRetryIDs = await runtime.restoreRetryIDs()
        XCTAssertEqual(metadataStore.upsertCallCount, 0)
        XCTAssertEqual(metadataStore.upsertAllCallCount, 0)
        XCTAssertEqual(archiveCalls, 0)
        XCTAssertEqual(retryCalls, 0)
        XCTAssertEqual(restoreCalls, 0)
        XCTAssertTrue(restoreRetryIDs.isEmpty)
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertNil(viewModel.lastDryRunLog)
    }

    func testIncompletePostPromotionRestoreDeniesGenericActionsWithOrWithoutIntegrityFailure() async throws {
        let phases: [VaultRestorePhase] = [.persistingActiveLocation, .openingInCubase]
        let failureReasons: [VaultRestoreFailureReason?] = [
            .activeDestinationIntegrityMismatch,
            nil,
        ]
        let integrityExplanation = "The restored Active copy no longer matches the verified archive manifest. It will not be opened; existing copies were kept for review."

        for phase in phases {
            for failureReason in failureReasons {
                let label = "\(phase)/\(failureReason?.rawValue ?? "catalogFailure")"
                let fixture = try ProjectVaultViewModelFixture()
                defer { fixture.cleanUp() }
                let baseSnapshot = try fixture.legacyReviewSnapshot(restoreID: UUID())
                var transfer = try XCTUnwrap(baseSnapshot.transfer, label)
                var restore = try XCTUnwrap(baseSnapshot.restore, label)
                restore.phase = phase
                restore.failureReason = failureReason
                restore.error = failureReason == nil ? "Catalog/Open did not complete" : "Active integrity mismatch"
                transfer.sourceURL = restore.destinationURL
                XCTAssertEqual(
                    transfer.sourceURL.standardizedFileURL,
                    restore.destinationURL.standardizedFileURL,
                    label
                )

                let cprURL = restore.destinationURL.appendingPathComponent("Integrity Song.cpr")
                try Data("rejected promoted Active bytes".utf8).write(to: cprURL)
                let cpr = ProjectVersion(
                    filePath: cprURL,
                    fileName: cprURL.lastPathComponent,
                    modifiedAt: Date()
                )
                let activeSong = Song(
                    folderPath: restore.destinationURL,
                    originalFolderName: fixture.song.originalFolderName,
                    displayTitle: fixture.song.displayTitle,
                    projectVersions: [cpr],
                    latestCPR: cpr
                )
                let runtime = RecordingProjectVaultRuntime(snapshots: [ProjectVaultRuntimeSnapshot(
                    record: baseSnapshot.record,
                    transfer: transfer,
                    restore: restore
                )])
                let metadataStore = RecordingSongUserMetadataStore()
                let revealed = RevealedURLBox()
                let viewModel = ArchiveBrowserViewModel(
                    context: TestToolContext.make(
                        settingsStore: fixture.settingsStore,
                        fileActions: CapturingTestFileActions(revealed: revealed)
                    ),
                    songMetadataStore: metadataStore,
                    archiveRootWatcher: NoopArchiveRootWatcher(),
                    projectVaultRuntime: runtime,
                    runtime: MusicHubRuntimeEnvironment(environment: [
                        MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                        MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
                    ])
                )
                viewModel.scannedSongs = [activeSong]
                viewModel.songs = [activeSong]
                viewModel.filteredSongs = [activeSong]

                await viewModel.refreshProjectVaultSnapshots()
                let sourceSong = try XCTUnwrap(viewModel.songs.first, label)
                viewModel.selectSong(sourceSong)
                let presentation = try XCTUnwrap(
                    viewModel.projectVaultPresentation(for: sourceSong),
                    label
                )

                if failureReason == .activeDestinationIntegrityMismatch {
                    XCTAssertEqual(presentation.state, .needsAttention, label)
                    XCTAssertEqual(presentation.explanation, integrityExplanation, label)
                } else {
                    XCTAssertEqual(presentation.state, .restoring, label)
                    XCTAssertEqual(
                        presentation.explanation,
                        ProjectVaultActivityExplanation.restore(phase),
                        label
                    )
                }
                XCTAssertEqual(presentation.primaryAction, .review, label)
                XCTAssertNil(presentation.reviewAction, label)
                XCTAssertNil(presentation.retryRestoreID, label)
                XCTAssertNil(viewModel.preferredRevealURL(for: sourceSong), label)
                XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: sourceSong), label)
                XCTAssertFalse(viewModel.canArchiveInProjectVault(sourceSong), label)

                viewModel.revealInFinder(url: sourceSong.folderPath)
                try? viewModel.openLatestCPR(for: sourceSong)
                if let selectedSong = viewModel.selectedSong {
                    viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: selectedSong))
                    try? viewModel.openLatestCPR(for: selectedSong)
                }
                viewModel.updateWorkflowStatus(for: sourceSong, status: .waitingFeedback)
                viewModel.updateWorkflowStatus(for: sourceSong, status: .done)
                viewModel.archiveInProjectVault(sourceSong)
                viewModel.performProjectVaultPrimaryAction(for: sourceSong)
                viewModel.retryReviewedProjectVaultRestore(for: sourceSong)
                try await Task.sleep(for: .milliseconds(20))

                XCTAssertEqual(metadataStore.upsertCallCount, 0, label)
                XCTAssertTrue(revealed.urls.isEmpty, label)
                XCTAssertNil(viewModel.lastDryRunLog, label)
                let archiveCalls = await runtime.archiveCallCount()
                let retryCalls = await runtime.retryCallCount()
                let restoreCalls = await runtime.restoreCallCount()
                let restoreRetryIDs = await runtime.restoreRetryIDs()
                XCTAssertEqual(archiveCalls, 0, label)
                XCTAssertEqual(retryCalls, 0, label)
                XCTAssertEqual(restoreCalls, 0, label)
                XCTAssertTrue(restoreRetryIDs.isEmpty, label)
            }
        }
    }

    func testSupersededArchivedOnlyRestoreDeniesReviewRetryAndGenericFileActions() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let legacySnapshot = try fixture.legacyReviewSnapshot(restoreID: UUID())
        var restore = try XCTUnwrap(legacySnapshot.restore)
        restore.phase = .superseded
        restore.supersededBy = UUID()
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        let generationURL = try XCTUnwrap(legacySnapshot.transfer?.destinationURL)
        try Data("retired restore archive".utf8).write(
            to: generationURL.appendingPathComponent("Retry Song.cpr")
        )
        try FileManager.default.removeItem(at: fixture.song.folderPath)
        let runtime = RecordingProjectVaultRuntime(snapshots: [ProjectVaultRuntimeSnapshot(
            record: legacySnapshot.record,
            transfer: legacySnapshot.transfer,
            restore: restore
        )])
        let revealed = RevealedURLBox()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(
                settingsStore: fixture.settingsStore,
                fileActions: CapturingTestFileActions(revealed: revealed)
            ),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
            ])
        )
        viewModel.scannedSongs = [fixture.song]
        viewModel.songs = [fixture.song]
        viewModel.filteredSongs = [fixture.song]

        await viewModel.refreshProjectVaultSnapshots()
        viewModel.setShowArchivedProjects(true)
        let archivedSong = try XCTUnwrap(viewModel.songs.first {
            $0.folderPath.standardizedFileURL == generationURL.standardizedFileURL
        })
        viewModel.selectSong(archivedSong)
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: archivedSong))

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertNil(presentation.reviewAction)
        XCTAssertNil(presentation.retryRestoreID)
        XCTAssertNil(viewModel.preferredRevealURL(for: archivedSong))

        viewModel.performProjectVaultPrimaryAction(for: archivedSong)
        viewModel.retryReviewedProjectVaultRestore(for: archivedSong)
        viewModel.revealInFinder(url: archivedSong.folderPath)
        try? viewModel.openLatestCPR(for: archivedSong)
        if let selectedSong = viewModel.selectedSong {
            viewModel.revealInFinder(url: selectedSong.folderPath)
            try? viewModel.openLatestCPR(for: selectedSong)
        }
        try await Task.sleep(for: .milliseconds(20))

        let retryIDs = await runtime.restoreRetryIDs()
        let archiveCalls = await runtime.archiveCallCount()
        XCTAssertTrue(retryIDs.isEmpty)
        XCTAssertEqual(archiveCalls, 0)
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertNil(viewModel.lastDryRunLog)
    }

    func testDestructiveCrashArchiveOnlyProjectStaysVisibleAndDeniesEveryAction() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let legacySnapshot = try fixture.legacyReviewSnapshot(restoreID: UUID())
        var transfer = try XCTUnwrap(legacySnapshot.transfer)
        transfer.state = .recoveryRequired
        transfer.error = VaultTransferError(
            origin: .removingActiveCopy,
            reason: .unknown,
            message: "Active-copy removal stopped after relaunch"
        )
        let generationURL = transfer.destinationURL
        try Data("verified destructive-crash archive".utf8).write(
            to: generationURL.appendingPathComponent("Retry Song.cpr")
        )
        try FileManager.default.removeItem(at: transfer.sourceURL)
        let runtime = RecordingProjectVaultRuntime(snapshots: [ProjectVaultRuntimeSnapshot(
            record: legacySnapshot.record,
            transfer: transfer,
            restore: nil
        )])
        let metadataStore = RecordingSongUserMetadataStore()
        let revealed = RevealedURLBox()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(
                settingsStore: fixture.settingsStore,
                fileActions: CapturingTestFileActions(revealed: revealed)
            ),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
            ])
        )
        viewModel.scannedSongs = []
        viewModel.songs = []
        viewModel.filteredSongs = []

        await viewModel.refreshProjectVaultSnapshots()
        viewModel.setShowArchivedProjects(true)
        try await Task.sleep(for: .milliseconds(20))
        guard let archivedSong = viewModel.songs.first(where: {
            $0.folderPath.standardizedFileURL == generationURL.standardizedFileURL
        }) else {
            return XCTFail("normalized destructive crash must remain visible from its verified generation")
        }
        viewModel.selectSong(archivedSong)
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: archivedSong))

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertFalse(viewModel.canArchiveInProjectVault(archivedSong))
        XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: archivedSong))
        XCTAssertNil(presentation.reviewAction)
        XCTAssertNil(presentation.retryRestoreID)
        XCTAssertNil(viewModel.preferredRevealURL(for: archivedSong))

        // Sidebar menu and board drag/drop both converge on this ViewModel entry.
        viewModel.updateWorkflowStatus(for: archivedSong, status: .waitingFeedback)
        viewModel.updateWorkflowStatus(for: archivedSong, status: .done)
        viewModel.performProjectVaultPrimaryAction(for: archivedSong)
        viewModel.retryReviewedProjectVaultRestore(for: archivedSong)
        viewModel.revealInFinder(url: archivedSong.folderPath)
        try? viewModel.openLatestCPR(for: archivedSong)
        if let selectedSong = viewModel.selectedSong {
            viewModel.revealInFinder(url: selectedSong.folderPath)
            try? viewModel.openLatestCPR(for: selectedSong)
        }
        try await Task.sleep(for: .milliseconds(20))

        let retryIDs = await runtime.restoreRetryIDs()
        let retryCalls = await runtime.retryCallCount()
        let restoreCalls = await runtime.restoreCallCount()
        let archiveCalls = await runtime.archiveCallCount()
        XCTAssertEqual(metadataStore.upsertCallCount, 0)
        XCTAssertEqual(metadataStore.upsertAllCallCount, 0)
        XCTAssertTrue(retryIDs.isEmpty)
        XCTAssertEqual(retryCalls, 0)
        XCTAssertEqual(restoreCalls, 0)
        XCTAssertEqual(archiveCalls, 0)
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertNil(viewModel.lastDryRunLog)
    }

    func testBindingBlockedArchivedOnlySongDeniesGenericRevealOpenAndGlobalShortcuts() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let restoreID = UUID()
        let legacySnapshot = try fixture.legacyReviewSnapshot(restoreID: restoreID)
        var restore = try XCTUnwrap(legacySnapshot.restore)
        restore.failureReason = .archiveTransferBindingUnavailable
        let generationURL = try XCTUnwrap(legacySnapshot.transfer?.destinationURL)
        let archivedCPR = generationURL.appendingPathComponent("Retry Song.cpr")
        try Data("archived-only fixture".utf8).write(to: archivedCPR)
        try FileManager.default.removeItem(at: fixture.song.folderPath)
        let snapshot = ProjectVaultRuntimeSnapshot(
            record: legacySnapshot.record,
            transfer: legacySnapshot.transfer,
            restore: restore
        )
        let runtime = RecordingProjectVaultRuntime(snapshots: [snapshot])
        let revealed = RevealedURLBox()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(
                settingsStore: fixture.settingsStore,
                fileActions: CapturingTestFileActions(revealed: revealed)
            ),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
            ])
        )
        viewModel.scannedSongs = [fixture.song]
        viewModel.songs = [fixture.song]
        viewModel.filteredSongs = [fixture.song]

        await viewModel.refreshProjectVaultSnapshots()
        viewModel.setShowArchivedProjects(true)
        let archivedSong = try XCTUnwrap(viewModel.songs.first {
            $0.folderPath.standardizedFileURL == generationURL.standardizedFileURL
        })
        viewModel.selectSong(archivedSong)
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: archivedSong))

        // The old Active path can reappear after this catalog snapshot (for
        // example, a restore or external sync). It must not turn the already
        // projected archive-destination Song into generic file authority.
        try FileManager.default.createDirectory(
            at: fixture.song.folderPath,
            withIntermediateDirectories: true
        )
        try Data("recreated active source".utf8).write(
            to: fixture.song.folderPath.appendingPathComponent("Recreated.cpr")
        )

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.primaryAction, .review)
        XCTAssertNil(presentation.reviewAction)
        XCTAssertNil(presentation.retryRestoreID)
        XCTAssertNil(
            viewModel.preferredRevealURL(for: archivedSong),
            "archived-only Project Vault cards must route through Restore/Get Local, not generic Reveal"
        )

        // Song Detail controls.
        viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: archivedSong))
        try? viewModel.openLatestCPR(for: archivedSong)
        // Global F/O shortcuts use these same selected-song entry points.
        if let selectedSong = viewModel.selectedSong {
            viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: selectedSong))
            try? viewModel.openLatestCPR(for: selectedSong)
        }
        viewModel.performProjectVaultPrimaryAction(for: archivedSong)

        let restoreRetryIDs = await runtime.restoreRetryIDs()
        let archiveCalls = await runtime.archiveCallCount()
        XCTAssertTrue(revealed.urls.isEmpty, "generic Finder actions must stay disabled")
        XCTAssertNil(viewModel.lastDryRunLog, "generic Open must not reach even the dry-run opener")
        XCTAssertTrue(restoreRetryIDs.isEmpty)
        XCTAssertEqual(archiveCalls, 0)
    }

    func testRecreatedActiveSourceBeforeRefreshKeepsDestructiveAndBindingBlockersNonActionable() async throws {
        enum Blocker: CaseIterable {
            case destructiveRecovery
            case archiveTransferBinding
        }

        for blocker in Blocker.allCases {
            let fixture = try ProjectVaultViewModelFixture()
            defer { fixture.cleanUp() }
            let legacySnapshot = try fixture.legacyReviewSnapshot(restoreID: UUID())
            var transfer = try XCTUnwrap(legacySnapshot.transfer)
            var restore = legacySnapshot.restore
            switch blocker {
            case .destructiveRecovery:
                transfer.state = .recoveryRequired
                transfer.error = VaultTransferError(
                    origin: .removingActiveCopy,
                    reason: .unknown,
                    message: "Active-copy removal stopped after relaunch"
                )
                restore = nil
            case .archiveTransferBinding:
                restore?.failureReason = .archiveTransferBindingUnavailable
            }
            try Data("verified blocked generation".utf8).write(
                to: transfer.destinationURL.appendingPathComponent("Retry Song.cpr")
            )
            try FileManager.default.removeItem(at: fixture.song.folderPath)

            let runtime = RecordingProjectVaultRuntime(snapshots: [ProjectVaultRuntimeSnapshot(
                record: legacySnapshot.record,
                transfer: transfer,
                restore: restore
            )])
            let metadataStore = RecordingSongUserMetadataStore()
            let revealed = RevealedURLBox()
            let viewModel = ArchiveBrowserViewModel(
                context: TestToolContext.make(
                    settingsStore: fixture.settingsStore,
                    fileActions: CapturingTestFileActions(revealed: revealed)
                ),
                songMetadataStore: metadataStore,
                archiveRootWatcher: NoopArchiveRootWatcher(),
                projectVaultRuntime: runtime,
                runtime: MusicHubRuntimeEnvironment(environment: [
                    MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                    MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
                ])
            )
            viewModel.scannedSongs = [fixture.song]
            viewModel.songs = [fixture.song]
            viewModel.filteredSongs = [fixture.song]

            // Simulate an external sync or restore recreating Active before the
            // next snapshot refresh/catalog rebuild chooses its projection path.
            try FileManager.default.createDirectory(
                at: fixture.song.folderPath,
                withIntermediateDirectories: true
            )
            try Data("recreated active source".utf8).write(
                to: fixture.song.folderPath.appendingPathComponent("Recreated.cpr")
            )
            await viewModel.refreshProjectVaultSnapshots()

            let sourceSong = try XCTUnwrap(viewModel.songs.first {
                $0.folderPath.standardizedFileURL == fixture.song.folderPath.standardizedFileURL
            })
            viewModel.selectSong(sourceSong)
            let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: sourceSong))
            XCTAssertEqual(presentation.state, .needsAttention, "\(blocker)")
            XCTAssertEqual(presentation.primaryAction, .review, "\(blocker)")
            XCTAssertNil(presentation.reviewAction, "\(blocker)")
            XCTAssertNil(presentation.retryRestoreID, "\(blocker)")
            XCTAssertFalse(viewModel.canArchiveInProjectVault(sourceSong), "\(blocker)")
            XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: sourceSong), "\(blocker)")
            XCTAssertNil(viewModel.preferredRevealURL(for: sourceSong), "\(blocker)")

            // Sidebar menu and board drag/drop converge here. Direct calls also
            // exercise the last authority boundary behind hidden UI controls.
            viewModel.updateWorkflowStatus(for: sourceSong, status: .waitingFeedback)
            viewModel.updateWorkflowStatus(for: sourceSong, status: .done)
            viewModel.archiveInProjectVault(sourceSong)
            viewModel.performProjectVaultPrimaryAction(for: sourceSong)
            viewModel.retryReviewedProjectVaultRestore(for: sourceSong)
            viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: sourceSong))
            viewModel.revealInFinder(url: sourceSong.folderPath)
            try? viewModel.openLatestCPR(for: sourceSong)
            if let selectedSong = viewModel.selectedSong {
                viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: selectedSong))
                try? viewModel.openLatestCPR(for: selectedSong)
            }
            for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(sourceSong.id) {
                try await Task.sleep(for: .milliseconds(10))
            }

            XCTAssertEqual(metadataStore.upsertCallCount, 0, "\(blocker)")
            XCTAssertEqual(metadataStore.upsertAllCallCount, 0, "\(blocker)")
            let archiveCalls = await runtime.archiveCallCount()
            let retryCalls = await runtime.retryCallCount()
            let restoreCalls = await runtime.restoreCallCount()
            let restoreRetryIDs = await runtime.restoreRetryIDs()
            XCTAssertEqual(archiveCalls, 0, "\(blocker)")
            XCTAssertEqual(retryCalls, 0, "\(blocker)")
            XCTAssertEqual(restoreCalls, 0, "\(blocker)")
            XCTAssertTrue(restoreRetryIDs.isEmpty, "\(blocker)")
            XCTAssertTrue(revealed.urls.isEmpty, "\(blocker)")
            XCTAssertNil(viewModel.lastDryRunLog, "\(blocker)")
        }
    }

    func testLocalArchivedOnlyVirtualSongUsesRestoreAuthorityAndNeverGenericOpenAuthority() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        var transfer = try XCTUnwrap(fixture.snapshot.transfer)
        let exactGeneration = fixture.root
            .appendingPathComponent("Archive/generations/\(transfer.projectID.description)", isDirectory: true)
            .appendingPathComponent(
                "generation-\(transfer.id.uuidString.lowercased())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: exactGeneration, withIntermediateDirectories: true)
        transfer.destinationURL = exactGeneration
        transfer.state = .archiveVerified
        transfer.error = nil
        transfer.manifest = VaultManifest(entries: [])
        transfer.manifestID = transfer.manifest?.id
        transfer.durability = .verifiedLocal
        try Data("verified local archive".utf8).write(
            to: transfer.destinationURL.appendingPathComponent("Retry Song.cpr")
        )
        try FileManager.default.removeItem(at: fixture.song.folderPath)
        let archivedRecord = ProjectRecord(
            id: fixture.snapshot.record.id,
            canonicalTitle: fixture.snapshot.record.canonicalTitle,
            locations: [ProjectLocation(
                rootID: UUID(),
                relativePath: "generations/\(transfer.projectID.description)/generation-\(transfer.id.uuidString.lowercased())",
                kind: .archive,
                availability: .local
            )],
            workflowState: fixture.snapshot.record.workflowState,
            latestManifestID: transfer.manifestID
        )
        let runtime = RecordingProjectVaultRuntime(
            snapshots: [ProjectVaultRuntimeSnapshot(record: archivedRecord, transfer: transfer)],
            restoreError: .archiveFailed("expected restore boundary stop")
        )
        let metadataStore = RecordingSongUserMetadataStore()
        let revealed = RevealedURLBox()
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(
                settingsStore: fixture.settingsStore,
                fileActions: CapturingTestFileActions(revealed: revealed)
            ),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
            ])
        )
        viewModel.scannedSongs = []
        viewModel.songs = []
        viewModel.filteredSongs = []

        await viewModel.refreshProjectVaultSnapshots()
        viewModel.setShowArchivedProjects(true)
        let archivedSong = try XCTUnwrap(viewModel.songs.first {
            $0.folderPath.standardizedFileURL == transfer.destinationURL.standardizedFileURL
        })
        viewModel.selectSong(archivedSong)
        let presentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: archivedSong))

        XCTAssertEqual(presentation.state, .archived)
        XCTAssertEqual(presentation.primaryAction, .restoreAndOpen)
        XCTAssertFalse(viewModel.canArchiveInProjectVault(archivedSong))
        XCTAssertFalse(viewModel.canMutateWorkflowStatus(for: archivedSong))
        XCTAssertNil(
            viewModel.preferredRevealURL(for: archivedSong),
            "archive-only virtual songs must not acquire generic filesystem authority"
        )

        // Direct detail and selected/global Open/Finder entry points are inert.
        viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: archivedSong))
        viewModel.revealInFinder(url: archivedSong.folderPath)
        try? viewModel.openLatestCPR(for: archivedSong)
        if let selectedSong = viewModel.selectedSong {
            viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: selectedSong))
            try? viewModel.openLatestCPR(for: selectedSong)
        }
        viewModel.updateWorkflowStatus(for: archivedSong, status: .done)
        viewModel.archiveInProjectVault(archivedSong)
        viewModel.retryReviewedProjectVaultRestore(for: archivedSong)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(archivedSong.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        let preRestoreArchiveCalls = await runtime.archiveCallCount()
        let preRestoreRetryCalls = await runtime.retryCallCount()
        let preRestoreRestoreCalls = await runtime.restoreCallCount()
        let preRestoreRetryIDs = await runtime.restoreRetryIDs()
        XCTAssertEqual(metadataStore.upsertCallCount, 0)
        XCTAssertEqual(metadataStore.upsertAllCallCount, 0)
        XCTAssertEqual(preRestoreArchiveCalls, 0)
        XCTAssertEqual(preRestoreRetryCalls, 0)
        XCTAssertEqual(preRestoreRestoreCalls, 0)
        XCTAssertTrue(preRestoreRetryIDs.isEmpty)
        XCTAssertTrue(revealed.urls.isEmpty)
        XCTAssertNil(viewModel.lastDryRunLog)

        // The dedicated Get Local & Open action is the sole mutating authority.
        viewModel.performProjectVaultPrimaryAction(for: archivedSong)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(archivedSong.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let restoreCalls = await runtime.restoreCallCount()
        XCTAssertEqual(restoreCalls, 1)
    }

    func testLegacyReviewRejectsUntrustedGenerationAuthoritiesWithoutRevealOrMutation() async throws {
        enum InvalidAuthority: CaseIterable {
            case disabledArchiveRoot
            case staleBookmark
            case outsideArchiveRoot
            case archiveRootItself
            case archiveStaging
        }

        for authority in InvalidAuthority.allCases {
            let fixture = try ProjectVaultViewModelFixture()
            defer { fixture.cleanUp() }
            let archiveRoot = fixture.root.appendingPathComponent("Archive", isDirectory: true)
            let generationURL: URL
            switch authority {
            case .disabledArchiveRoot:
                generationURL = archiveRoot.appendingPathComponent("generations/project/generation", isDirectory: true)
                try fixture.settingsStore.updateSettings { settings in
                    guard let index = settings.musicRoots.firstIndex(where: { $0.role == .archive }) else { return }
                    settings.musicRoots[index].isEnabled = false
                }
            case .staleBookmark:
                generationURL = archiveRoot.appendingPathComponent("generations/project/generation", isDirectory: true)
                try fixture.settingsStore.updateSettings { settings in
                    guard let index = settings.musicRoots.firstIndex(where: { $0.role == .archive }) else { return }
                    settings.musicRoots[index].securityScopedBookmark = Data([0x00, 0x01, 0x02])
                }
            case .outsideArchiveRoot:
                generationURL = fixture.song.folderPath
            case .archiveRootItself:
                generationURL = archiveRoot
            case .archiveStaging:
                generationURL = archiveRoot.appendingPathComponent(".niko-staging/unsafe", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: generationURL, withIntermediateDirectories: true)
            let restoreID = UUID()
            let runtime = RecordingProjectVaultRuntime(snapshots: [
                try fixture.legacyReviewSnapshot(
                    restoreID: restoreID,
                    generationURL: generationURL
                ),
            ])
            let revealed = RevealedURLBox()
            let viewModel = fixture.makeViewModel(
                runtime: runtime,
                fileActions: CapturingTestFileActions(revealed: revealed)
            )
            await viewModel.refreshProjectVaultSnapshots()

            let presentation = viewModel.projectVaultPresentation(for: fixture.song)
            XCTAssertNil(presentation?.reviewAction, "\(authority) must not create Finder authority")
            XCTAssertNil(presentation?.retryRestoreID, "\(authority) must not create retry authority")
            if presentation != nil {
                viewModel.performProjectVaultPrimaryAction(for: fixture.song)
            }

            XCTAssertTrue(revealed.urls.isEmpty)
            let retryIDs = await runtime.restoreRetryIDs()
            XCTAssertTrue(retryIDs.isEmpty)
            XCTAssertFalse(viewModel.projectVaultBusySongIDs.contains(fixture.song.id))
        }
    }

    func testInvalidTerminalTransferNeverCreatesArchivedSongOrGenericRevealOpenAuthority() async throws {
        enum InvalidDestination: CaseIterable {
            case outsideArchiveRoot
            case archiveRootItself
            case archiveStaging
        }

        for invalidDestination in InvalidDestination.allCases {
            let fixture = try ProjectVaultViewModelFixture()
            defer { fixture.cleanUp() }
            let archiveRoot = fixture.root.appendingPathComponent("Archive", isDirectory: true)
            let destinationURL: URL
            switch invalidDestination {
            case .outsideArchiveRoot:
                destinationURL = fixture.root.appendingPathComponent("Outside/generation", isDirectory: true)
            case .archiveRootItself:
                destinationURL = archiveRoot
            case .archiveStaging:
                destinationURL = archiveRoot.appendingPathComponent(".niko-staging/unsafe", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            let projectURL = destinationURL.appendingPathComponent("Unsafe Archived Song.cpr")
            try Data("unsafe terminal fixture".utf8).write(to: projectURL)
            try FileManager.default.removeItem(at: fixture.song.folderPath)

            var transfer = try XCTUnwrap(fixture.snapshot.transfer)
            transfer.sourceURL = fixture.song.folderPath
            transfer.destinationURL = destinationURL
            transfer.state = .archiveVerified
            transfer.error = nil
            transfer.manifest = VaultManifest(entries: [])
            transfer.manifestID = transfer.manifest?.id
            transfer.durability = .verifiedLocal
            let snapshot = ProjectVaultRuntimeSnapshot(
                record: fixture.snapshot.record,
                transfer: transfer
            )
            let runtime = RecordingProjectVaultRuntime(snapshots: [snapshot])
            let revealed = RevealedURLBox()
            let viewModel = ArchiveBrowserViewModel(
                context: TestToolContext.make(
                    settingsStore: fixture.settingsStore,
                    fileActions: CapturingTestFileActions(revealed: revealed)
                ),
                archiveRootWatcher: NoopArchiveRootWatcher(),
                projectVaultRuntime: runtime,
                runtime: MusicHubRuntimeEnvironment(environment: [
                    MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
                    MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
                ])
            )
            viewModel.scannedSongs = [fixture.song]
            viewModel.songs = [fixture.song]
            viewModel.filteredSongs = [fixture.song]

            await viewModel.refreshProjectVaultSnapshots()
            viewModel.setShowArchivedProjects(true)

            let destinationPath = destinationURL.standardizedFileURL.path
            let unsafeVirtualSongs = viewModel.songs.filter {
                $0.folderPath.standardizedFileURL.path == destinationPath
            }
            if let unsafeSong = unsafeVirtualSongs.first {
                viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: unsafeSong))
                try? viewModel.openLatestCPR(for: unsafeSong)
            }

            XCTAssertTrue(
                unsafeVirtualSongs.isEmpty,
                "\(invalidDestination) must not become a virtual Song with raw folder authority"
            )
            XCTAssertTrue(revealed.urls.isEmpty, "\(invalidDestination) must not authorize generic Reveal")
            XCTAssertNil(viewModel.lastDryRunLog, "\(invalidDestination) must not authorize generic Open")
        }
    }

    func testArchiveFailureRefreshesPersistedOwnershipAndHidesArchiveNow() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let runtime = RecordingProjectVaultRuntime(
            archiveError: .archiveFailed("forced provider failure"),
            archiveFailureSnapshots: [fixture.snapshot]
        )
        let viewModel = fixture.makeViewModel(runtime: runtime)
        XCTAssertTrue(viewModel.canArchiveInProjectVault(fixture.song))

        viewModel.archiveInProjectVault(fixture.song)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(viewModel.canArchiveInProjectVault(fixture.song))
        XCTAssertEqual(viewModel.projectVaultPresentation(for: fixture.song)?.primaryAction, .retry)
        let archiveCallCount = await runtime.archiveCallCount()
        XCTAssertEqual(archiveCallCount, 1)
    }

    func testCapacityPostponementDoesNotScheduleDoneRetry() async throws {
        let fixture = try ProjectVaultViewModelFixture(workflowStatus: .done)
        defer { fixture.cleanUp() }
        let runtime = RecordingProjectVaultRuntime(
            archiveError: .activityPostponed(.insufficientArchiveCapacity)
        )
        let viewModel = fixture.makeViewModel(runtime: runtime)

        viewModel.archiveInProjectVault(fixture.song, trigger: .workflowDone)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(viewModel.projectVaultRetryTasks.isEmpty)
        XCTAssertTrue(viewModel.projectVaultRetryAttemptCounts.isEmpty)
        let archiveCallCount = await runtime.archiveCallCount()
        XCTAssertEqual(archiveCallCount, 1)
    }

    func testTransientPostponementSchedulesOneBoundedRetryAndRefreshDoesNotDuplicate() async throws {
        let fixture = try ProjectVaultViewModelFixture(workflowStatus: .done)
        defer { fixture.cleanUp() }
        let runtime = RecordingProjectVaultRuntime(
            archiveError: .activityPostponed(.recentWriteActivity)
        )
        let viewModel = fixture.makeViewModel(runtime: runtime)
        defer { viewModel.projectVaultRetryTasks.values.forEach { $0.cancel() } }

        viewModel.archiveInProjectVault(fixture.song, trigger: .workflowDone)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(viewModel.projectVaultRetryTasks.count, 1)
        XCTAssertEqual(viewModel.projectVaultRetryAttemptCounts[fixture.song.id], 1)

        await viewModel.refreshProjectVaultSnapshots()
        try await Task.sleep(for: .milliseconds(25))
        let archiveCallCount = await runtime.archiveCallCount()
        XCTAssertEqual(archiveCallCount, 1)
        XCTAssertEqual(viewModel.projectVaultRetryTasks.count, 1)
        XCTAssertEqual(viewModel.projectVaultRetryAttemptCounts[fixture.song.id], 1)
    }

    func testIncrementalScanCompletionDoesNotOverwriteNewerProjectVaultStatus() async throws {
        let fixture = try ProjectVaultViewModelFixture()
        defer { fixture.cleanUp() }
        let watcher = TestArchiveRootWatcher()
        let runtime = RecordingProjectVaultRuntime(snapshots: [fixture.snapshot])
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: fixture.settingsStore),
            archiveRootWatcher: watcher,
            projectVaultRuntime: runtime
        )
        viewModel.scannedSongs = [fixture.song]
        viewModel.songs = [fixture.song]
        viewModel.filteredSongs = [fixture.song]
        await viewModel.refreshProjectVaultSnapshots()

        for _ in 0..<100 where viewModel.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        setenv("NIKO_MUSIC_HUB_TEST_INCREMENTAL_HOLD_NS", "250000000", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_TEST_INCREMENTAL_HOLD_NS") }
        let changedURL = fixture.song.folderPath.appendingPathComponent("new-preview.wav")
        FileManager.default.createFile(atPath: changedURL.path, contents: Data("fixture".utf8))
        watcher.simulateFilesystemChange(paths: [changedURL])

        for _ in 0..<100 where !viewModel.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(viewModel.isScanning)
        viewModel.performProjectVaultPrimaryAction(for: fixture.song)
        for _ in 0..<100 where viewModel.projectVaultBusySongIDs.contains(fixture.song.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(viewModel.statusMessage, "Project Vault retry completed and verified.")

        for _ in 0..<100 where viewModel.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertEqual(viewModel.statusMessage, "Project Vault retry completed and verified.")
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
        XCTAssertTrue(viewModel.statusMessage?.contains("No project file (.cpr or .als) yet") == true)
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
        _ = await viewModel.indexPersistTask?.value
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

    func testFilesystemOverflowAndPendingPathOverflowFallBackToFullRescan() async throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubIncrementalOverflow-\(UUID().uuidString)", isDirectory: true)
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

        let songB = root.appendingPathComponent("Song B", isDirectory: true)
        try FileManager.default.createDirectory(at: songB, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songB.appendingPathComponent("Song B.cpr").path,
            contents: Data("fixture".utf8)
        )

        watcher.simulateFilesystemOverflow()
        let watcherOverflowDeadline = Date().addingTimeInterval(2)
        while !viewModel.songs.contains(where: { $0.displayTitle == "Song B" }),
              Date() < watcherOverflowDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(Set(viewModel.songs.map(\.displayTitle)), ["Song A", "Song B"])

        let songC = root.appendingPathComponent("Song C", isDirectory: true)
        try FileManager.default.createDirectory(at: songC, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songC.appendingPathComponent("Song C.cpr").path,
            contents: Data("fixture".utf8)
        )

        // The changed song is deliberately absent from this event batch. A
        // partial incremental scan would miss it; the 1,025th distinct path
        // must instead compact to one full-rescan request.
        watcher.simulateFilesystemChange(paths: (0...1_024).map {
            root.appendingPathComponent("storm-noise-\($0)", isDirectory: true)
        })

        let deadline = Date().addingTimeInterval(2)
        while !viewModel.songs.contains(where: { $0.displayTitle == "Song C" }), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(Set(viewModel.songs.map(\.displayTitle)), ["Song A", "Song B", "Song C"])
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
        _ = await viewModel.indexPersistTask?.value
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

private struct ProjectVaultViewModelFixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let settingsStore: UserDefaultsSettingsStore
    let song: Song
    let snapshot: ProjectVaultRuntimeSnapshot

    init(workflowStatus: ProjectWorkflowStatus? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-view-model-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        let folder = active.appendingPathComponent("Retry Song", isDirectory: true)
        let projectID = ProjectID()
        let generation = archive.appendingPathComponent(
            "generations/\(projectID.description)/retry",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)

        let activeRoot = StoredMusicRoot(role: .active, url: active)
        let archiveRoot = StoredMusicRoot(role: .archive, url: archive)
        suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestPersistenceError.forced
        }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
        settingsStore = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var settings = AppSettings.default
        settings.musicRoots = [activeRoot, archiveRoot]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeRoot.id,
            archiveRootID: archiveRoot.id,
            rolloutStage: .privateBeta
        )
        try settingsStore.saveSettings(settings)

        song = Song(
            folderPath: folder,
            originalFolderName: "Retry Song",
            displayTitle: "Retry Song",
            workflowStatus: workflowStatus
        )
        let record = ProjectRecord(
            id: projectID,
            canonicalTitle: "Retry Song",
            locations: [ProjectLocation(
                rootID: activeRoot.id,
                relativePath: "Retry Song",
                kind: .active
            )],
            workflowState: workflowStatus
        )
        var transfer = VaultTransferRecord(
            projectID: projectID,
            sourceURL: folder,
            stagingURL: archive.appendingPathComponent(".niko-staging/retry"),
            destinationURL: generation,
            state: .failedRecoverable
        )
        transfer.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "provider retry"
        )
        snapshot = ProjectVaultRuntimeSnapshot(record: record, transfer: transfer)
    }

    func legacyReviewSnapshot(
        restoreID: UUID,
        generationURL: URL? = nil
    ) throws -> ProjectVaultRuntimeSnapshot {
        var transfer = try XCTUnwrap(snapshot.transfer)
        let generation = generationURL ?? root
            .appendingPathComponent(
                "Archive/generations/\(transfer.projectID.description)",
                isDirectory: true
            )
            .appendingPathComponent(
                "generation-\(transfer.id.uuidString.lowercased())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        transfer.destinationURL = generation
        transfer.state = .archiveVerified
        transfer.error = nil
        transfer.manifest = VaultManifest(entries: [])
        transfer.manifestID = transfer.manifest?.id
        transfer.durability = .verifiedLocal
        var restore = VaultRestoreRecord(
            id: restoreID,
            projectID: snapshot.record.id,
            archiveGenerationURL: generation,
            stagingURL: root.appendingPathComponent("Active/.niko-staging/\(restoreID.uuidString.lowercased())"),
            destinationURL: song.folderPath,
            manifest: try XCTUnwrap(transfer.manifest),
            archiveTransferID: transfer.id,
            archiveTransferState: transfer.state,
            requiresArchiveMaterialization: false
        )
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        return ProjectVaultRuntimeSnapshot(
            record: snapshot.record,
            transfer: transfer,
            restore: restore
        )
    }

    @MainActor
    func makeViewModel(
        runtime: any ProjectVaultOperating,
        fileActions: (any FileActions)? = nil
    ) -> ArchiveBrowserViewModel {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore, fileActions: fileActions),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime
        )
        viewModel.scannedSongs = [song]
        viewModel.songs = [song]
        viewModel.filteredSongs = [song]
        return viewModel
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class CancellationAwareScanGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ScanResult, Error>?
    private var waiting = false
    private var cancelled = false

    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiting
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func wait() async throws -> ScanResult {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                waiting = true
                let shouldCancel = cancelled
                if !shouldCancel {
                    self.continuation = continuation
                }
                lock.unlock()
                if shouldCancel {
                    continuation.resume(throwing: CancellationError())
                }
            }
        }, onCancel: {
            cancel()
        })
    }

    func release() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: ScanResult())
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

private final class ScanReleaseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation != nil
    }

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

private actor RecordingProjectVaultRuntime: ProjectVaultOperating {
    private var archivedSong: Song?
    private var snapshotValues: [ProjectVaultRuntimeSnapshot]
    private var archiveCalls = 0
    private var retryCalls = 0
    private var restoreCalls = 0
    private let retryFailureState: VaultTransferState?
    private let refreshFailsAfterRetry: Bool
    private let retryGate: ScanReleaseGate?
    private let archiveError: ProjectVaultRuntimeError?
    private let archiveFailureSnapshots: [ProjectVaultRuntimeSnapshot]
    private let restoreError: ProjectVaultRuntimeError?
    private let restoreFailureSnapshots: [ProjectVaultRuntimeSnapshot]
    private let restoreRetryGate: ScanReleaseGate?
    private let restoreRetryError: ProjectVaultRuntimeError?
    private var restoreRetryCalls: [UUID] = []
    private var didRetry = false

    init(
        snapshots: [ProjectVaultRuntimeSnapshot] = [],
        retryFailureState: VaultTransferState? = nil,
        refreshFailsAfterRetry: Bool = false,
        retryGate: ScanReleaseGate? = nil,
        archiveError: ProjectVaultRuntimeError? = nil,
        archiveFailureSnapshots: [ProjectVaultRuntimeSnapshot] = [],
        restoreError: ProjectVaultRuntimeError? = nil,
        restoreFailureSnapshots: [ProjectVaultRuntimeSnapshot] = [],
        restoreRetryGate: ScanReleaseGate? = nil,
        restoreRetryError: ProjectVaultRuntimeError? = nil
    ) {
        snapshotValues = snapshots
        self.retryFailureState = retryFailureState
        self.refreshFailsAfterRetry = refreshFailsAfterRetry
        self.retryGate = retryGate
        self.archiveError = archiveError
        self.archiveFailureSnapshots = archiveFailureSnapshots
        self.restoreError = restoreError
        self.restoreFailureSnapshots = restoreFailureSnapshots
        self.restoreRetryGate = restoreRetryGate
        self.restoreRetryError = restoreRetryError
    }

    func snapshots() async throws -> [ProjectVaultRuntimeSnapshot] {
        if didRetry, refreshFailsAfterRetry {
            throw ProjectVaultRuntimeError.archiveFailed("forced refresh failure")
        }
        return snapshotValues
    }

    func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
        archiveCalls += 1
        archivedSong = song
        if let archiveError {
            if !archiveFailureSnapshots.isEmpty {
                snapshotValues = archiveFailureSnapshots
            }
            throw archiveError
        }
        return ProjectVaultRuntimeSnapshot(
            record: ProjectRecord(
                canonicalTitle: song.effectiveDisplayTitle,
                locations: [],
                workflowState: song.workflowStatus
            ),
            transfer: nil
        )
    }

    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        restoreCalls += 1
        if !restoreFailureSnapshots.isEmpty {
            snapshotValues = restoreFailureSnapshots
        }
        if let restoreError {
            throw restoreError
        }
        fatalError("successful restore is not part of this test")
    }

    func retry(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRuntimeSnapshot {
        retryCalls += 1
        await retryGate?.waitForRelease()
        didRetry = true
        var transfer = snapshot.transfer
        if let retryFailureState {
            if var updatedTransfer = transfer {
                updatedTransfer.state = retryFailureState
                if retryFailureState == .recoveryRequired {
                    updatedTransfer.error = VaultTransferError(
                        origin: .copyingToArchiveStaging,
                        reason: .occupiedDestination,
                        message: "manual review required"
                    )
                }
                transfer = updatedTransfer
            }
        } else {
            transfer?.state = .archiveVerified
            transfer?.error = nil
            transfer?.nextRetryAt = nil
        }
        let updated = ProjectVaultRuntimeSnapshot(record: snapshot.record, transfer: transfer)
        snapshotValues = [updated]
        if retryFailureState != nil {
            throw ProjectVaultRuntimeError.archiveFailed("forced retry failure")
        }
        return updated
    }

    func retryRestore(id: UUID) async throws -> VaultRestoreRecord {
        restoreRetryCalls.append(id)
        await restoreRetryGate?.waitForRelease()
        if let restoreRetryError { throw restoreRetryError }
        guard var restore = snapshotValues.compactMap(\.restore).first(where: { $0.id == id }) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        restore.failureReason = nil
        restore.error = nil
        restore.completedAt = Date()
        snapshotValues = snapshotValues.map {
            ProjectVaultRuntimeSnapshot(record: $0.record, transfer: $0.transfer, restore: nil)
        }
        return restore
    }

    func recoverAtLaunch() async {}

    func lastArchivedSong() -> Song? { archivedSong }
    func archiveCallCount() -> Int { archiveCalls }
    func retryCallCount() -> Int { retryCalls }
    func restoreCallCount() -> Int { restoreCalls }
    func restoreRetryIDs() -> [UUID] { restoreRetryCalls }
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

private final class RecordingSongUserMetadataStore: SongUserMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedUpserts = 0
    private var recordedBulkUpserts = 0

    var upsertCallCount: Int {
        lock.withLock { recordedUpserts }
    }

    var upsertAllCallCount: Int {
        lock.withLock { recordedBulkUpserts }
    }

    func loadAll() throws -> [String: SongUserMetadata] { [:] }

    func upsert(_ metadata: SongUserMetadata) throws {
        lock.withLock { recordedUpserts += 1 }
    }

    func upsertAll(_ metadata: [SongUserMetadata]) throws {
        lock.withLock { recordedBulkUpserts += 1 }
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
