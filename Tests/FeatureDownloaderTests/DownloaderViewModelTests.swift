@testable import AppCore
@testable import FeatureDownloader
import XCTest

@MainActor
final class DownloaderViewModelTests: XCTestCase {
    func testStartDownloadSetsDownloadingSynchronouslyAndRejectsDuplicateStarts() async throws {
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .completed,
            progress: 1,
            message: "Downloaded"
        )
        let inbox = RecordingOutputInboxStore()
        let useCase = FakeDownloaderUseCase(job: job, delay: .milliseconds(10))
        let viewModel = makeViewModel(
            useCase: useCase,
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/first"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()

        XCTAssertEqual(viewModel.downloadState, .downloading)
        viewModel.startDownload()
        try await waitUntil { useCase.callCount == 1 }
        XCTAssertEqual(useCase.receivedURLs, [URL(string: "https://example.com/first")!])
    }

    func testCompletedDownloadUsesCapturedSourceURLForInboxMetadata() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = try makeExistingFile(named: "download.wav", in: directory)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .completed,
            progress: 1,
            message: "Downloaded",
            outputFileURLs: [outputURL]
        )
        let inbox = RecordingOutputInboxStore()
        let useCase = FakeDownloaderUseCase(job: job, delay: .milliseconds(20))
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: useCase,
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/original"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()
        viewModel.urlText = "https://example.com/edited"

        try await waitUntil { inbox.items.count == 1 }
        XCTAssertEqual(inbox.items.first?.metadata["dlSourceURL"], "https://example.com/original")
        XCTAssertEqual(viewModel.outputURLs, [outputURL])
    }

    func testInboxAddFailureKeepsDownloadCompletedWithHandoffWarning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = try makeExistingFile(named: "download.mp3", in: directory)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .completed,
            progress: 1,
            message: "Downloaded",
            outputFileURLs: [outputURL]
        )
        let inbox = RecordingOutputInboxStore(addError: FixtureOutputInboxError.forced)
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()

        try await waitUntil { viewModel.outputURLs == [outputURL] }
        XCTAssertEqual(viewModel.downloadState, .completed)
        XCTAssertTrue(viewModel.errorMessage?.contains("Output Inbox") == true)
    }

    func testFormatSelectionLoadsFromInjectedPreferences() throws {
        let suiteName = "DownloaderViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let originalStandard = UserDefaults.standard.data(forKey: "downloader.formatSelection")
        defer {
            if let originalStandard {
                UserDefaults.standard.set(originalStandard, forKey: "downloader.formatSelection")
            } else {
                UserDefaults.standard.removeObject(forKey: "downloader.formatSelection")
            }
        }
        UserDefaults.standard.set(
            try JSONEncoder().encode(DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .mp3)),
            forKey: "downloader.formatSelection"
        )
        let preferences = UserDefaultsPreferenceStore(userDefaults: defaults)
        preferences.set(
            try JSONEncoder().encode(DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .wav)),
            forKey: "downloader.formatSelection"
        )

        let job = Job(sourceToolID: "downloader", title: "Download")
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: RecordingOutputInboxStore(),
            preferences: preferences
        )

        XCTAssertEqual(viewModel.formatSelection.mediaKind, .audioOnly)
        XCTAssertEqual(viewModel.formatSelection.audioContainer, .wav)
    }

    private func makeViewModel(
        outputFolder: URL = URL(fileURLWithPath: "/tmp/downloader-vm"),
        useCase: FakeDownloaderUseCase,
        jobRunner: any JobRunning,
        outputInboxStore: any OutputInboxStore,
        preferences: any PreferenceStore = UserDefaultsPreferenceStore()
    ) -> DownloaderViewModel {
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: FixtureSettingsStore(settings: AppSettings(
                outputFolder: StoredFolderLocation(url: outputFolder)
            )),
            preferences: preferences,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics()
        )
        return DownloaderViewModel(
            context: context,
            useCase: useCase
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloaderViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExistingFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("download".utf8).write(to: url)
        return url
    }
}

private final class FakeDownloaderUseCase: DownloaderUseCaseRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let job: Job
    private let delay: Duration?
    private var storedURLs: [URL] = []
    private var storedOptions: [DownloadJobOptions] = []

    init(job: Job, delay: Duration? = nil) {
        self.job = job
        self.delay = delay
    }

    var callCount: Int {
        lock.downloaderTestWithLock { storedURLs.count }
    }

    var receivedURLs: [URL] {
        lock.downloaderTestWithLock { storedURLs }
    }

    func simulateAndEnqueue(url: URL, options: DownloadJobOptions) async throws -> Job {
        lock.downloaderTestWithLock {
            storedURLs.append(url)
            storedOptions.append(options)
        }
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return job
    }
}

private final class StaticJobRunner: JobRunning, @unchecked Sendable {
    private let job: Job

    init(job: Job) {
        self.job = job
    }

    func listJobs() -> [Job] { [job] }

    func job(id: Job.ID) -> Job? {
        job.id == id ? job : nil
    }

    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        XCTFail("DownloaderViewModel tests should not enqueue through the context job runner")
        return job
    }

    func cancelJob(id: Job.ID) {}
}

private final class RecordingOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private let addError: Error?
    private var storedItems: [OutputInboxItem] = []

    init(addError: Error? = nil) {
        self.addError = addError
    }

    var items: [OutputInboxItem] {
        lock.downloaderTestWithLock { storedItems }
    }

    func listItems() throws -> [OutputInboxItem] { items }

    func addItem(_ item: OutputInboxItem) throws {
        if let addError {
            throw addError
        }
        lock.downloaderTestWithLock {
            storedItems.append(item)
        }
    }

    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private enum FixtureOutputInboxError: LocalizedError {
    case forced

    var errorDescription: String? {
        "forced inbox failure"
    }
}

private struct FixtureSettingsStore: SettingsStore {
    var settings: AppSettings

    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws {}
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

private struct FixtureFileActions: FileActions {
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

private struct FixtureDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}

private func waitUntil(
    timeoutAttempts: Int = 50,
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<timeoutAttempts {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for condition")
}
