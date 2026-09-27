@testable import AppCore
@testable import FeatureDownloader
import Foundation
import XCTest

/// Actual fixture chain: ExternalProcessRunning -> YtDlpDownloader ->
/// DownloaderUseCase -> real JobRunner -> DownloaderViewModel.
/// No real helpers or API calls; all output roots are unique disposable
/// directories with cleanup.
@MainActor
final class DownloaderMixedPlaylistIntegrationTests: XCTestCase {
    func testMixedPlaylistFreshPlusExistingThenNonzeroFailureExposesOutputsWithoutOverwrite() async throws {
        let outputDir = try makeTemporaryDirectory(prefix: "DownloaderMixedPlaylist")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let existingBytes = Data("pre-existing-bytes-\(UUID().uuidString)".utf8)
        let existingURL = outputDir.appendingPathComponent("existing-\(UUID().uuidString).mp4")
        try existingBytes.write(to: existingURL)

        let freshName = "fresh-\(UUID().uuidString).mp4"
        let freshBytes = Data("fresh-download-bytes-\(UUID().uuidString)".utf8)
        let freshURL = outputDir.appendingPathComponent(freshName)

        let locator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { $0 == "/fixture/yt-dlp" }
        )
        let versionRunner = IntegrationVersionRunner()
        let healthChecker = YtDlpHealthChecker(runner: versionRunner, referenceDate: YtDlpVersionPolicy.parseVersionDate("2026.09.27"), locator: locator)
        let jobRunner = JobRunner()
        let settings = AppSettings(
            outputFolder: StoredFolderLocation(url: outputDir),
            helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/fixture/yt-dlp"))
        )
        let settingsStore = FixtureIntegrationSettingsStore(settings: settings)
        let downloadRunner = MixedPlaylistIntegrationRunner(
            existingPath: existingURL.path,
            freshURL: freshURL,
            freshBytes: freshBytes
        )
        let downloader = YtDlpDownloader(runner: downloadRunner)
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker,
            jobRunner: jobRunner,
            settingsStore: settingsStore,
            simulateRunner: versionRunner,
            locator: locator
        )
        let inbox = RecordingIntegrationInboxStore()
        let viewModel = makeIntegrationViewModel(
            settingsStore: settingsStore,
            useCase: useCase,
            jobRunner: jobRunner,
            outputInboxStore: inbox,
            healthChecker: healthChecker
        )

        let sourceURL = "https://example.com/playlist?list=abc"
        viewModel.urlText = sourceURL
        viewModel.playlistMode = .playlist
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()

        try await waitUntil { viewModel.downloadState != .downloading }
        guard case let .failed(message) = viewModel.downloadState else {
            XCTFail("Expected failed for mixed playlist with nonzero exit, got \(viewModel.downloadState)")
            return
        }
        XCTAssertTrue(message.contains("Video unavailable"), "unexpected message: \(message)")
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)

        // Failed partial playlist still exposes verified outputs.
        XCTAssertEqual(
            Set(viewModel.outputURLs.map(\.standardizedFileURL.path)),
            Set([existingURL.standardizedFileURL.path, freshURL.standardizedFileURL.path])
        )
        XCTAssertEqual(inbox.items.count, 2)
        XCTAssertEqual(
            Set(inbox.items.map(\.fileURL.standardizedFileURL.path)),
            Set([existingURL.standardizedFileURL.path, freshURL.standardizedFileURL.path])
        )
        // Captured sourceURL is preserved in inbox metadata, not edited input.
        for item in inbox.items {
            XCTAssertEqual(item.metadata["dlSourceURL"], sourceURL)
        }
        // Playlist request omits single-video flag and caps entries.
        let downloadArguments = try XCTUnwrap(downloadRunner.requests.first?.arguments)
        XCTAssertFalse(downloadArguments.contains("--no-playlist"))
        XCTAssertTrue(downloadArguments.contains("--max-downloads"))

        // viewModel.job is the initial queued snapshot; inspect the terminal
        // real JobRunner snapshot by ID for the failed mixed job.
        let jobID = try XCTUnwrap(viewModel.job?.id)
        let terminal = try XCTUnwrap(jobRunner.job(id: jobID))
        XCTAssertEqual(terminal.state, .failed)
        XCTAssertNil(terminal.failureReason)
        XCTAssertEqual(
            Set(terminal.outputFileURLs.map(\.standardizedFileURL.path)),
            Set([existingURL.standardizedFileURL.path, freshURL.standardizedFileURL.path])
        )

        // Bytes unchanged, no overwrite of the pre-existing item.
        XCTAssertEqual(try Data(contentsOf: existingURL), existingBytes)
        XCTAssertEqual(try Data(contentsOf: freshURL), freshBytes)
    }

    func testFailureWithNoOutputMarkerCannotClaimCompletion() async throws {
        let outputDir = try makeTemporaryDirectory(prefix: "DownloaderMixedEmpty")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let locator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { $0 == "/fixture/yt-dlp" }
        )
        let versionRunner = IntegrationVersionRunner()
        let healthChecker = YtDlpHealthChecker(runner: versionRunner, referenceDate: YtDlpVersionPolicy.parseVersionDate("2026.09.27"), locator: locator)
        let jobRunner = JobRunner()
        let settings = AppSettings(
            outputFolder: StoredFolderLocation(url: outputDir),
            helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/fixture/yt-dlp"))
        )
        let settingsStore = FixtureIntegrationSettingsStore(settings: settings)
        let downloader = YtDlpDownloader(runner: EmptyFailureIntegrationRunner())
        let useCase = DownloaderUseCase(
            downloader: downloader,
            healthChecker: healthChecker,
            jobRunner: jobRunner,
            settingsStore: settingsStore,
            simulateRunner: versionRunner,
            locator: locator
        )
        let inbox = RecordingIntegrationInboxStore()
        let viewModel = makeIntegrationViewModel(
            settingsStore: settingsStore,
            useCase: useCase,
            jobRunner: jobRunner,
            outputInboxStore: inbox,
            healthChecker: healthChecker
        )

        viewModel.urlText = "https://example.com/watch?v=missing"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()

        try await waitUntil { viewModel.downloadState != .downloading }
        guard case .failed = viewModel.downloadState else {
            XCTFail("Expected failed when failure has no outputs, got \(viewModel.downloadState)")
            return
        }
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        XCTAssertNotEqual(viewModel.statusMessage, "Downloaded")
        XCTAssertTrue(viewModel.outputURLs.isEmpty)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    // MARK: - Seams (reuse ViewModel helper setup; real useCase is injected)

    private func makeIntegrationViewModel(
        settingsStore: FixtureIntegrationSettingsStore,
        useCase: DownloaderUseCase,
        jobRunner: JobRunner,
        outputInboxStore: RecordingIntegrationInboxStore,
        healthChecker: YtDlpHealthChecker
    ) -> DownloaderViewModel {
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: settingsStore,
            preferences: FixtureIntegrationPreferenceStore(),
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: FixtureIntegrationFileActions(),
            diagnostics: FixtureIntegrationDiagnostics()
        )
        return DownloaderViewModel(
            context: context,
            useCase: useCase,
            healthChecker: healthChecker,
            formatSelection: .default,
            debounceDuration: .milliseconds(5)
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitUntil(
        timeoutAttempts: Int = 100,
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutAttempts {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for condition")
    }
}

// MARK: - Fixture runners (no real helpers or API calls)

private struct IntegrationVersionRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        if request.arguments.contains("--simulate") {
            return ExternalProcessResult(exitCode: 0, standardOutput: "Playlist Title", standardError: "")
        }
        return ExternalProcessResult(exitCode: 0, standardOutput: "2026.08.19", standardError: "")
    }
}

private final class MixedPlaylistIntegrationRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let existingPath: String
    private let freshURL: URL
    private let freshBytes: Data
    private var storedRequests: [ExternalProcessRequest] = []

    var requests: [ExternalProcessRequest] {
        lock.withLock { storedRequests }
    }

    init(existingPath: String, freshURL: URL, freshBytes: Data) {
        self.existingPath = existingPath
        self.freshURL = freshURL
        self.freshBytes = freshBytes
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { storedRequests.append(request) }
        // Fresh regular contained file written by this run; the pre-existing
        // file is only referenced, never overwritten.
        FileManager.default.createFile(atPath: freshURL.path, contents: freshBytes)
        let stdout = [
            "[download] \(existingPath) has already been downloaded",
            "[download] Destination: \(freshURL.path)",
            "NIKO_MUSIC_HUB_FILE:\(freshURL.path)",
        ].joined(separator: "\n") + "\n"
        return ExternalProcessResult(
            exitCode: 1,
            standardOutput: stdout,
            standardError: "ERROR: [youtube] abc: Video unavailable"
        )
    }
}

private struct EmptyFailureIntegrationRunner: ExternalProcessRunning {
    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        ExternalProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "ERROR: [youtube] abc: Video unavailable"
        )
    }
}

// MARK: - Fixture stores

private struct FixtureIntegrationSettingsStore: SettingsStore {
    var settings: AppSettings

    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws {}
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

/// Local in-memory preferences so the fixture never reads the host's
/// persisted format selection and never writes to standard UserDefaults.
private final class FixtureIntegrationPreferenceStore: PreferenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var bools: [String: Bool] = [:]
    private var datas: [String: Data] = [:]
    private var strings: [String: String] = [:]

    func bool(forKey key: String) -> Bool? {
        lock.withLock { bools[key] }
    }

    func set(_ value: Bool, forKey key: String) {
        lock.withLock { bools[key] = value }
    }

    func data(forKey key: String) -> Data? {
        lock.withLock { datas[key] }
    }

    func set(_ data: Data, forKey key: String) {
        lock.withLock { datas[key] = data }
    }

    func string(forKey key: String) -> String? {
        lock.withLock { strings[key] }
    }

    func set(_ value: String, forKey key: String) {
        lock.withLock { strings[key] = value }
    }

    func removeObject(forKey key: String) {
        lock.withLock {
            bools.removeValue(forKey: key)
            datas.removeValue(forKey: key)
            strings.removeValue(forKey: key)
        }
    }
}

private final class RecordingIntegrationInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedItems: [OutputInboxItem] = []

    var items: [OutputInboxItem] {
        lock.withLock { storedItems }
    }

    func listItems() throws -> [OutputInboxItem] { items }

    func addItem(_ item: OutputInboxItem) throws {
        lock.withLock { storedItems.append(item) }
    }

    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct FixtureIntegrationFileActions: FileActions {
    @MainActor
    func chooseOutputFolder() -> URL? { nil }

    @MainActor
    func chooseDirectory(prompt: String) -> URL? { nil }

    @MainActor
    func chooseExecutable(prompt: String) -> URL? { nil }

    @MainActor
    func chooseAudioFile(prompt: String) -> URL? { nil }

    @MainActor
    func revealInFinder(_ url: URL) {}
}

private struct FixtureIntegrationDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}
