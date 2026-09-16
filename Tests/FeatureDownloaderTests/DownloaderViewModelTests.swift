@testable import AppCore
@testable import FeatureDownloader
import XCTest

@MainActor
final class DownloaderViewModelTests: XCTestCase {
    func testValidatedHTTPURLRejectsDeceptiveSchemesAndMissingHosts() {
        XCTAssertNil(DownloaderViewModel.validatedHTTPURL("httpx://example.com/file"))
        XCTAssertNil(DownloaderViewModel.validatedHTTPURL("file:///tmp/audio.wav"))
        XCTAssertNil(DownloaderViewModel.validatedHTTPURL("https:///missing-host"))
        XCTAssertNotNil(DownloaderViewModel.validatedHTTPURL("https://example.com/file"))
    }

    func testCanceledDebounceNeverInvokesHealthChecker() async throws {
        let runner = SequencedHealthRunner()
        let checker = YtDlpHealthChecker(
            runner: runner,
            fileExists: { _ in true }
        )
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: Job(sourceToolID: "downloader", title: "Download")),
            jobRunner: StaticJobRunner(job: Job(sourceToolID: "downloader", title: "Download")),
            outputInboxStore: RecordingOutputInboxStore(),
            healthChecker: checker,
            debounceDuration: .milliseconds(40)
        )
        viewModel.urlText = "https://example.com/a"
        viewModel.urlTextDidChange()
        viewModel.clearInput()

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(runner.callCount, 0)
        XCTAssertEqual(viewModel.downloadState, .idle)
    }

    func testSlowURLAResultCannotOverwriteURLB() async throws {
        let runner = SequencedHealthRunner(firstDelay: .milliseconds(150), firstExitCode: 1)
        let checker = YtDlpHealthChecker(runner: runner, fileExists: { _ in true })
        let job = Job(sourceToolID: "downloader", title: "Download")
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: RecordingOutputInboxStore(),
            healthChecker: checker,
            debounceDuration: .milliseconds(5)
        )
        viewModel.urlText = "https://example.com/a"
        viewModel.urlTextDidChange()
        try await waitUntil { runner.callCount == 1 }

        viewModel.urlText = "https://example.com/b"
        viewModel.urlTextDidChange()
        try await waitUntil { viewModel.downloadState == .readyToDownload }
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(viewModel.downloadState, .readyToDownload)
        XCTAssertEqual(viewModel.detectedFileName, "b")
        XCTAssertEqual(runner.callCount, 2)
    }

    func testClearInputCancelsInFlightHealthCheck() async throws {
        let runner = CancellableHealthRunner()
        let checker = YtDlpHealthChecker(runner: runner, fileExists: { _ in true })
        let job = Job(sourceToolID: "downloader", title: "Download")
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: RecordingOutputInboxStore(),
            healthChecker: checker,
            debounceDuration: .milliseconds(5)
        )
        viewModel.urlText = "https://example.com/a"
        viewModel.urlTextDidChange()
        try await waitUntil { runner.didStart }

        viewModel.clearInput()

        try await waitUntil { runner.wasCanceled }
        XCTAssertEqual(viewModel.downloadState, .idle)
    }

    func testViewModelCanDeallocateWithPendingDebounce() async throws {
        let job = Job(sourceToolID: "downloader", title: "Download")
        weak var weakViewModel: DownloaderViewModel?
        do {
            var viewModel: DownloaderViewModel? = makeViewModel(
                useCase: FakeDownloaderUseCase(job: job),
                jobRunner: StaticJobRunner(job: job),
                outputInboxStore: RecordingOutputInboxStore(),
                debounceDuration: .seconds(5)
            )
            viewModel?.urlText = "https://example.com/a"
            viewModel?.urlTextDidChange()
            weakViewModel = viewModel
            viewModel = nil
        }

        for _ in 0..<20 where weakViewModel != nil {
            await Task.yield()
        }
        XCTAssertNil(weakViewModel)
    }

    func testSubmitIfReadyStartsOnlyWhenReady() async throws {
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .completed,
            progress: 1,
            message: "Downloaded"
        )
        let useCase = FakeDownloaderUseCase(job: job, delay: .milliseconds(10))
        let viewModel = makeViewModel(
            useCase: useCase,
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: RecordingOutputInboxStore()
        )
        viewModel.urlText = "https://example.com/first"

        viewModel.downloadState = .idle
        viewModel.submitIfReady()
        XCTAssertEqual(viewModel.downloadState, .idle)
        XCTAssertEqual(useCase.callCount, 0)

        viewModel.downloadState = .checkingURL
        viewModel.submitIfReady()
        XCTAssertEqual(viewModel.downloadState, .checkingURL)
        XCTAssertEqual(useCase.callCount, 0)

        viewModel.downloadState = .readyToDownload
        viewModel.submitIfReady()
        XCTAssertEqual(viewModel.downloadState, .downloading)
        try await waitUntil { useCase.callCount == 1 }
        XCTAssertEqual(useCase.receivedURLs, [URL(string: "https://example.com/first")!])
    }

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

    func testCancelDownloadSetsCanceledState() async throws {
        let runner = JobRunner()
        let runningJob = runner.enqueue(title: "Download", sourceToolID: "downloader") { _ in
            try await Task.sleep(for: .seconds(30))
        }
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: runningJob),
            jobRunner: runner,
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()
        try await waitUntil { viewModel.job != nil }

        viewModel.cancelDownload()

        try await waitUntil { viewModel.downloadState == .canceled }
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.statusMessage, DownloaderCopy.downloadCanceledDetail)
        XCTAssertTrue(inbox.items.isEmpty)
        XCTAssertEqual(viewModel.urlText, "https://example.com/audio")

        viewModel.startDownload()
        XCTAssertEqual(viewModel.downloadState, .downloading)
        runner.cancelJob(id: runningJob.id)
    }

    func testCanceledJobIsNotFailed() async throws {
        let canceledJob = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .canceled,
            message: "Canceled"
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: canceledJob),
            jobRunner: StaticJobRunner(job: canceledJob),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()

        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .canceled)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.statusMessage, DownloaderCopy.downloadCanceledDetail)
        XCTAssertTrue(inbox.items.isEmpty)
        XCTAssertEqual(viewModel.urlText, "https://example.com/audio")

        viewModel.startDownload()
        XCTAssertEqual(viewModel.downloadState, .downloading)
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

    func testShowsDeterminateProgress() async throws {
        let runner = JobRunner()
        let progressGate = DownloadTestGate()
        let finishGate = DownloadTestGate()
        let job = runner.enqueue(title: "Download", sourceToolID: "downloader") { progress in
            await progressGate.wait()
            progress.update(progress: 0.42, message: nil)
            await finishGate.wait()
        }
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: runner,
            outputInboxStore: RecordingOutputInboxStore()
        )

        XCTAssertEqual(viewModel.progress, 0)
        XCTAssertFalse(viewModel.showsDeterminateProgress)
        XCTAssertEqual(
            DownloaderViewModel.formatElapsed(
                since: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 12)
            ),
            "Elapsed 0:12"
        )

        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.job != nil }
        XCTAssertEqual(viewModel.progress, 0)
        XCTAssertFalse(viewModel.showsDeterminateProgress)

        progressGate.signal()
        try await waitUntil { viewModel.progress > 0 }
        XCTAssertEqual(viewModel.progress, 0.42, accuracy: 0.0001)
        XCTAssertTrue(viewModel.showsDeterminateProgress)

        finishGate.signal()
        runner.cancelJob(id: job.id)
    }

    private func makeViewModel(
        outputFolder: URL = URL(fileURLWithPath: "/tmp/downloader-vm"),
        useCase: FakeDownloaderUseCase,
        jobRunner: any JobRunning,
        outputInboxStore: any OutputInboxStore,
        preferences: any PreferenceStore = UserDefaultsPreferenceStore(),
        healthChecker: YtDlpHealthChecker = YtDlpHealthChecker(),
        debounceDuration: Duration = .milliseconds(500)
    ) -> DownloaderViewModel {
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: FixtureSettingsStore(settings: AppSettings(
                outputFolder: StoredFolderLocation(url: outputFolder),
                helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/fixture/yt-dlp"))
            )),
            preferences: preferences,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics()
        )
        return DownloaderViewModel(
            context: context,
            useCase: useCase,
            healthChecker: healthChecker,
            debounceDuration: debounceDuration
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

private final class SequencedHealthRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let firstDelay: Duration?
    private let firstExitCode: Int32
    private var storedCallCount = 0

    init(firstDelay: Duration? = nil, firstExitCode: Int32 = 0) {
        self.firstDelay = firstDelay
        self.firstExitCode = firstExitCode
    }

    var callCount: Int {
        lock.downloaderTestWithLock { storedCallCount }
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        let index = lock.downloaderTestWithLock { () -> Int in
            let current = storedCallCount
            storedCallCount += 1
            return current
        }
        if index == 0, let firstDelay {
            try? await Task.sleep(for: firstDelay)
        }
        let exitCode = index == 0 ? firstExitCode : 0
        return ExternalProcessResult(
            exitCode: exitCode,
            standardOutput: exitCode == 0 ? "2099.01.01\n" : "",
            standardError: exitCode == 0 ? "" : "unsupported"
        )
    }
}

private final class CancellableHealthRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDidStart = false
    private var storedWasCanceled = false

    var didStart: Bool { lock.downloaderTestWithLock { storedDidStart } }
    var wasCanceled: Bool { lock.downloaderTestWithLock { storedWasCanceled } }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.downloaderTestWithLock { storedDidStart = true }
        do {
            try await Task.sleep(for: .seconds(10))
            return ExternalProcessResult(exitCode: 0, standardOutput: "2099.01.01\n", standardError: "")
        } catch {
            lock.downloaderTestWithLock { storedWasCanceled = true }
            throw error
        }
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

private final class DownloadTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var signaled = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if signaled {
                signaled = false
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume()
        } else {
            signaled = true
            lock.unlock()
        }
    }
}
