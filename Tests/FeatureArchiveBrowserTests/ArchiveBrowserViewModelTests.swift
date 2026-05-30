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

    func testDevArchiveRootEnvBootstrapsWhenSettingsEmpty() async throws {
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
        XCTAssertEqual(
            try store.loadSettings().archiveRoots.map(\.path),
            [devRoot.standardizedFileURL.path]
        )
    }

    func testNormalLaunchFiltersFixtureTempAndMissingRootsFromSavedSettings() async throws {
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

        XCTAssertEqual(viewModel.roots.map(\.path), [publicRoot.standardizedFileURL.path])
        XCTAssertEqual(
            try store.loadSettings().archiveRoots.map(\.path),
            [publicRoot.standardizedFileURL.path]
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
        viewModel.searchQuery = "Neon Hook"
        viewModel.applySearchFilter()
        XCTAssertEqual(viewModel.filteredSongs.count, 1)
        XCTAssertEqual(viewModel.filteredSongs.first?.displayTitle, "Neon Hook")
        let songID = try XCTUnwrap(viewModel.filteredSongs.first?.id)
        XCTAssertFalse(viewModel.searchMatchSummaries[songID, default: ""].isEmpty)
    }

    func testSearchFindsSkippedRootLabel() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.searchQuery = "LOOSE_FILE.txt"
        viewModel.applySearchFilter()

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

    func testExportDiagnosticsIncludesSkippedSearchContext() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.searchQuery = "LOOSE_FILE.txt"
        viewModel.applySearchFilter()
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
        viewModel.searchQuery = "project"
        viewModel.applySearchFilter()
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
        viewModel.searchQuery = "nts nly"
        viewModel.applySearchFilter()
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
        viewModel.searchQuery = "neon hk"
        viewModel.applySearchFilter()
        XCTAssertEqual(viewModel.filteredSongs.count, 1)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("search_query=neon hk"))
        XCTAssertTrue(text.contains("search_match title=Neon Hook"))
        XCTAssertTrue(text.contains("summary="))
    }

    func testLoadsCachedIndexWhenRootsMatch() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        let suiteName = "FeatureArchiveBrowserTests.\(UUID())"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let settingsStore = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")

        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        let root = buildDir.appendingPathComponent("NikoMusicHubCacheRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
        XCTAssertEqual(viewModel.songs.count, 1)
        XCTAssertEqual(viewModel.songs.first?.displayTitle, "Cached Song")
        XCTAssertTrue(viewModel.statusMessage?.contains("cache") == true)
    }

    func testFirstRunOnboardingWhenRootsEmpty() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        if ArchiveDefaultRootPolicy.bootstrapRoot() != nil {
            throw XCTSkip("Developer bootstrap root is present on this machine.")
        }
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
        let afterUpdate = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Neon Hook" })
        XCTAssertEqual(afterUpdate.effectiveDisplayTitle, "Electric Neon")
        let storedMeta = try metadataStore.loadAll()
        XCTAssertEqual(storedMeta[neon.id]?.virtualTitle, "Electric Neon")

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

        reloaded.searchQuery = "glowstick"
        reloaded.applySearchFilter()
        XCTAssertEqual(reloaded.filteredSongs.count, 1)
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
        viewModel.selectedShelf = .byCollaborator
        viewModel.selectedCollaboratorID = collaborator.id
        viewModel.applySearchFilter()
        XCTAssertEqual(viewModel.filteredSongs.count, 1)

        viewModel.searchQuery = "studio"
        viewModel.applySearchFilter()
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
        let before = viewModel.songsForSelectedShelf().count
        let target = try XCTUnwrap(viewModel.songs.first)
        viewModel.setSongHidden(target, hidden: true)
        XCTAssertEqual(viewModel.songsForSelectedShelf().count, before - 1)
        viewModel.showHiddenSongs = true
        XCTAssertEqual(viewModel.songsForSelectedShelf().count, before)
    }

    func testCreateNewSongInTempRoot() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN") }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("index.sqlite")
        let metadataStore = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: metadataStore,
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = [root]
        let created = try viewModel.createNewSong(
            request: NewSongRequest(name: "CI Song", root: root, appNote: "test")
        )
        XCTAssertEqual(created.originalFolderName, "CI Song")
        XCTAssertTrue(viewModel.songs.contains(where: { $0.id == created.id }))
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

}
