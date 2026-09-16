import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveRootBookmarkPersistTests: XCTestCase {
    func testAddRootsPersistsBookmarkData() throws {
        let fixture = try IsolatedBookmarkSettingsFixture()
        defer { fixture.tearDown() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-052-not-a-music-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = fixture.makeViewModel(bookmarkProvider: StubArchiveBookmarkProvider())
        viewModel.addRoots([root])

        let reloaded = try fixture.store.loadSettings()
        let stored = try XCTUnwrap(reloaded.musicRoots.first { $0.role == .scanOnly })
        XCTAssertEqual(stored.securityScopedBookmark, Data([1, 2, 3]))
        XCTAssertEqual(stored.pathFallback, root.standardizedFileURL.path)
        XCTAssertEqual(
            reloaded.archiveRoots.first?.securityScopedBookmark,
            Data([1, 2, 3])
        )
    }

    func testAddRootsKeepsPathWhenBookmarkCannotBeSaved() throws {
        let fixture = try IsolatedBookmarkSettingsFixture()
        defer { fixture.tearDown() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-052-bookmark-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = fixture.makeViewModel(bookmarkProvider: FailingArchiveBookmarkProvider())
        viewModel.addRoots([root])

        XCTAssertEqual(
            viewModel.persistenceWarningMessage,
            "Archive root bookmark could not be saved for \(root.lastPathComponent). The folder may need to be chosen again after quit."
        )
        let reloaded = try fixture.store.loadSettings()
        let stored = try XCTUnwrap(reloaded.musicRoots.first { $0.role == .scanOnly })
        XCTAssertNil(stored.securityScopedBookmark)
        XCTAssertEqual(stored.pathFallback, root.standardizedFileURL.path)
        XCTAssertEqual(viewModel.roots.map(\.path), [root.standardizedFileURL.path])
    }

    func testLegacyArchiveRootJSONDecodesMissingBookmarkAsNil() throws {
        let json = Data(#"{"path":"/tmp/nmh-052-legacy-root"}"#.utf8)
        let decoded = try JSONDecoder().decode(StoredArchiveRoot.self, from: json)
        XCTAssertEqual(decoded.path, "/tmp/nmh-052-legacy-root")
        XCTAssertNil(decoded.securityScopedBookmark)
    }

    func testCorruptBookmarkFailsClosedWithoutPathFallback() {
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-052-fallback-\(UUID().uuidString)", isDirectory: true)
        let root = StoredMusicRoot(
            role: .scanOnly,
            url: fallback,
            securityScopedBookmark: Data([0xFF, 0x00, 0x01])
        )
        XCTAssertThrowsError(try root.resolvedURL(using: FoundationSecurityScopedBookmarks()))
        XCTAssertEqual(root.pathFallback, fallback.standardizedFileURL.path)
    }

    func testChooseRootCreatesBookmarkWhilePanelScopeIsValid() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("Choose Archive Roots"))
        XCTAssertTrue(source.contains("Select one or more folders that contain Cubase or Ableton song folders."))
        XCTAssertTrue(source.contains("makeBookmark(for: url)"))
        XCTAssertTrue(source.contains("addRoots(urls, bookmarksByURL: bookmarksByURL)"))
    }
}

private struct IsolatedBookmarkSettingsFixture {
    let suiteName: String
    let store: UserDefaultsSettingsStore
    let runtime: MusicHubRuntimeEnvironment
    private let userDefaults: UserDefaults

    init() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
        suiteName = "FeatureArchiveBrowserTests.NMH052.\(UUID())"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        store = UserDefaultsSettingsStore(userDefaults: userDefaults, key: "settings")
        runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.settingsSuiteKey: suiteName,
        ])
    }

    @MainActor
    func makeViewModel(
        bookmarkProvider: any SecurityScopedBookmarkProviding
    ) -> ArchiveBrowserViewModel {
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

private struct StubArchiveBookmarkProvider: SecurityScopedBookmarkProviding {
    func makeBookmark(for url: URL) throws -> Data { Data([1, 2, 3]) }
}

private struct FailingArchiveBookmarkProvider: SecurityScopedBookmarkProviding {
    func makeBookmark(for url: URL) throws -> Data {
        throw SecurityScopedBookmarkError.missingBookmark
    }
}
