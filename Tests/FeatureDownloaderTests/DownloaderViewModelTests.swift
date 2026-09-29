@testable import AppCore
import Darwin
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
            locator: HelperToolLocator(
                managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
                systemDirectories: [],
                isExecutable: { $0 == "/fixture/yt-dlp" }
            )
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
        let checker = YtDlpHealthChecker(
            runner: runner,
            locator: HelperToolLocator(
                managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
                systemDirectories: [],
                isExecutable: { $0 == "/fixture/yt-dlp" }
            )
        )
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
        let checker = YtDlpHealthChecker(
            runner: runner,
            locator: HelperToolLocator(
                managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
                systemDirectories: [],
                isExecutable: { $0 == "/fixture/yt-dlp" }
            )
        )
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
        let key = "downloader.formatSelection"
        let injected = InMemoryTestPreferenceStore()
        injected.set(
            try JSONEncoder().encode(DownloadFormatSelection(mediaKind: .audioOnly, audioContainer: .wav)),
            forKey: key
        )

        let job = Job(sourceToolID: "downloader", title: "Download")
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: RecordingOutputInboxStore(),
            preferences: injected
        )

        XCTAssertNotEqual(viewModel.formatSelection, DownloadFormatSelection.default)
        XCTAssertEqual(viewModel.formatSelection.mediaKind, .audioOnly)
        XCTAssertEqual(viewModel.formatSelection.audioContainer, .wav)

        // Control: an empty injected store yields the built-in default.
        let emptyViewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: RecordingOutputInboxStore(),
            preferences: InMemoryTestPreferenceStore()
        )
        XCTAssertEqual(emptyViewModel.formatSelection, DownloadFormatSelection.default)
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

    func testPostProcessingShowsConvertingStatusAndNextItemClearsIt() async throws {
        let runner = JobRunner()
        let convertGate = DownloadTestGate()
        let nextItemGate = DownloadTestGate()
        let finishGate = DownloadTestGate()
        let job = runner.enqueue(title: "Download", sourceToolID: "downloader") { progress in
            progress.log("NIKO_PROGRESS:{'status': 'finished', '_percent_str': '100.0%'}")
            progress.update(progress: 1, message: nil)
            await convertGate.wait()
            progress.log("NIKO_POSTPROCESS:started:ExtractAudio")
            await nextItemGate.wait()
            progress.log("NIKO_PROGRESS:{'status': 'downloading', '_percent_str': '  3.0%'}")
            await finishGate.wait()
        }
        let viewModel = makeViewModel(
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: runner,
            outputInboxStore: RecordingOutputInboxStore()
        )

        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.progress == 1 }
        XCTAssertNil(viewModel.postProcessingStatus)

        convertGate.signal()
        try await waitUntil { viewModel.postProcessingStatus != nil }
        XCTAssertEqual(viewModel.postProcessingStatus, DownloaderCopy.convertingAudio)
        XCTAssertFalse(viewModel.slowHintVisible)

        nextItemGate.signal()
        try await waitUntil { viewModel.postProcessingStatus == nil }

        finishGate.signal()
        runner.cancelJob(id: job.id)
    }

    // Typed policy: only `.downloadAlreadyExists` with verified contained
    // outputs may present the already-exists status. Display text and marker
    // logs never decide.
    func testAlreadyDownloadedWithValidExistingFileRegistersInInbox() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = try makeExistingFile(named: "existing-\(UUID().uuidString).mp4", in: directory)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [outputURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState == .completed }
        XCTAssertEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        XCTAssertEqual(viewModel.outputURLs, [outputURL.standardizedFileURL])
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.items.first?.fileURL.standardizedFileURL.path, outputURL.standardizedFileURL.path)
    }

    func testAlreadyDownloadedWithAbsentFileStaysFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing-\(UUID().uuidString).mp4")
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [missing]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("No output files found after download."))
        XCTAssertTrue(inbox.items.isEmpty)
        XCTAssertTrue(viewModel.outputURLs.isEmpty)
    }

    func testAlreadyDownloadedWithDirectoryStaysFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let subdir = directory.appendingPathComponent("subdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [subdir]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("No output files found after download."))
        XCTAssertTrue(inbox.items.isEmpty)
    }

    func testAlreadyDownloadedWithOutsidePathStaysFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outsideDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let outsideFile = try makeExistingFile(named: "outside-\(UUID().uuidString).mp4", in: outsideDir)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [outsideFile]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("No output files found after download."))
        XCTAssertTrue(inbox.items.isEmpty)
        XCTAssertTrue(viewModel.outputURLs.isEmpty)
    }

    func testAlreadyDownloadedWithSymlinkEscapeStaysFailed() async throws {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloaderVM-symlink-\(UUID().uuidString)", isDirectory: true)
        let outputDir = baseDir.appendingPathComponent("output", isDirectory: true)
        let outsideDir = baseDir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let outsideFile = outsideDir.appendingPathComponent("secret-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: outsideFile.path, contents: Data("x".utf8))
        let linkURL = outputDir.appendingPathComponent("link")
        do {
            try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: outsideDir.path)
        } catch {
            throw XCTSkip("Symlinks are not supported on this platform.")
        }
        let escapeURL = linkURL.appendingPathComponent(outsideFile.lastPathComponent)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [escapeURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: outputDir,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("No output files found after download."))
        XCTAssertTrue(inbox.items.isEmpty)
    }

    func testAlreadyDownloadedWithInboxFailureReportsFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = try makeExistingFile(named: "handoff-\(UUID().uuidString).mp4", in: directory)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
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
        try await waitUntil { viewModel.downloadState != .downloading }
        guard case let .failed(message) = viewModel.downloadState else {
            XCTFail("Expected failed when inbox handoff fails, got \(viewModel.downloadState)")
            return
        }
        XCTAssertTrue(message.contains("Output Inbox"))
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
    }

    func testNormalSuccessRegistersExistingOutput() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = try makeExistingFile(named: "normal-\(UUID().uuidString).mp4", in: directory)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .completed,
            progress: 1,
            message: "Downloaded",
            outputFileURLs: [outputURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState == .completed }
        XCTAssertEqual(viewModel.statusMessage, "Downloaded")
        XCTAssertEqual(viewModel.outputURLs, [outputURL])
        XCTAssertEqual(inbox.items.count, 1)
    }

    // Captured destination must survive a settings mutation during a queued
    // download. Candidates are verified beneath the captured directory only;
    // a same-name file appearing only in the mutated directory must not verify.
    func testSettingsMutationDuringJobUsesCapturedOutputDirectory() async throws {
        let originalDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: originalDir) }
        let mutatedDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: mutatedDir) }
        let fileName = "shared-\(UUID().uuidString).mp4"
        // Only the mutated directory contains the same-name file.
        let mutatedFile = try makeExistingFile(named: fileName, in: mutatedDir)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [mutatedFile]
        )
        let inbox = RecordingOutputInboxStore()
        let store = MutableFolderSettingsStore(outputFolder: originalDir)
        let useCase = FakeDownloaderUseCase(job: job, delay: .milliseconds(30))
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: store,
            preferences: InMemoryTestPreferenceStore(),
            outputInboxStore: inbox,
            jobRunner: StaticJobRunner(job: job),
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics()
        )
        let viewModel = DownloaderViewModel(context: context, useCase: useCase)
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        // Mutate settings while the start is still queued.
        store.outputFolder = mutatedDir
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("No output files found after download."))
        XCTAssertTrue(viewModel.outputURLs.isEmpty)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    // A real failure with verified outputs must stay failed while still
    // exposing/inboxing those outputs. Typed reason is nil (not a pure skip);
    // marker logs are included only to prove they never decide presentation.
    func testAlreadyMarkerPlusRealErrorPropagatesFailureWhileExposingVerifiedOutput() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let verifiedURL = try makeExistingFile(named: "already-\(UUID().uuidString).mp4", in: directory)
        let marker = "[download] \(verifiedURL.path) has already been downloaded"
        let realError = "ERROR: unable to download video data: HTTP Error 403: Forbidden"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "Download failed: \(realError)",
            failureReason: nil,
            logEntries: [JobLogEntry(message: marker), JobLogEntry(message: realError)],
            outputFileURLs: [verifiedURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        guard case let .failed(message) = viewModel.downloadState else {
            XCTFail("Expected failed when a real error follows an already marker, got \(viewModel.downloadState)")
            return
        }
        XCTAssertTrue(message.contains("ERROR:"))
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        // Valid existing output is still exposed/inboxed, but state stays failed.
        XCTAssertEqual(viewModel.outputURLs, [verifiedURL.standardizedFileURL])
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.items.first?.fileURL.standardizedFileURL.path, verifiedURL.standardizedFileURL.path)
    }

    // Stall plus verified outputs must stay failed while still exposing
    // verified files. A display message alone must never make a skip.
    func testAlreadyMarkerPlusStallWithoutErrorSubstringStaysFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let verifiedURL = try makeExistingFile(named: "already-stall-\(UUID().uuidString).mp4", in: directory)
        let marker = "[download] \(verifiedURL.path) has already been downloaded"
        let stallMessage = "Download failed: \(DownloadStallMonitor.stallErrorMessage)"
        XCTAssertFalse(stallMessage.contains("ERROR:"))
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: stallMessage,
            failureReason: nil,
            logEntries: [JobLogEntry(message: marker)],
            outputFileURLs: [verifiedURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        guard case let .failed(message) = viewModel.downloadState else {
            XCTFail("Expected failed when stall follows an already marker, got \(viewModel.downloadState)")
            return
        }
        XCTAssertEqual(message, stallMessage)
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        XCTAssertEqual(viewModel.outputURLs, [verifiedURL.standardizedFileURL])
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.items.first?.fileURL.standardizedFileURL.path, verifiedURL.standardizedFileURL.path)
    }

    // Generic non-ERROR download failure with verified outputs must stay failed
    // while exposing verified files.
    func testAlreadyMarkerPlusNonErrorDownloadFailureStaysFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let verifiedURL = try makeExistingFile(named: "already-generic-\(UUID().uuidString).mp4", in: directory)
        let marker = "[download] \(verifiedURL.path) has already been downloaded"
        let failureMessage = "Download failed: connection reset by peer"
        XCTAssertFalse(failureMessage.contains("ERROR:"))
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: failureMessage,
            failureReason: nil,
            logEntries: [JobLogEntry(message: marker), JobLogEntry(message: failureMessage)],
            outputFileURLs: [verifiedURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        guard case let .failed(message) = viewModel.downloadState else {
            XCTFail("Expected failed for non-ERROR failure with marker, got \(viewModel.downloadState)")
            return
        }
        XCTAssertEqual(message, failureMessage)
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        XCTAssertEqual(viewModel.outputURLs, [verifiedURL.standardizedFileURL])
        XCTAssertEqual(inbox.items.count, 1)
    }

    // Typed all-existing with a radically changed message and no marker logs
    // still registers the verified contained file as already-exists.
    func testTypedAllExistingWithRadicallyChangedMessageAndNoMarkerLogsRegistersAlreadyExists() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = try makeExistingFile(named: "typed-skip-\(UUID().uuidString).mp4", in: directory)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "Radically changed informational outcome 7F3A-\(UUID().uuidString): nothing to fetch.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [outputURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/original"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState == .completed }
        XCTAssertEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        XCTAssertEqual(viewModel.outputURLs, [outputURL.standardizedFileURL])
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.items.first?.fileURL.standardizedFileURL.path, outputURL.standardizedFileURL.path)
        XCTAssertEqual(inbox.items.first?.metadata["dlSourceURL"], "https://example.com/original")
    }

    // An untyped job with identical old outputNotFound/skip-looking display
    // text and marker logs stays failed, even with valid output candidates.
    // Valid outputs are still exposed/inboxed.
    func testUntypedSkipLookingTextWithMarkerLogsStaysFailedWhileExposingOutputs() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = try makeExistingFile(named: "untyped-skip-\(UUID().uuidString).mp4", in: directory)
        let marker = "[download] \(outputURL.path) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: nil,
            logEntries: [JobLogEntry(message: marker)],
            outputFileURLs: [outputURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("No output files found after download."))
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        XCTAssertEqual(viewModel.outputURLs, [outputURL.standardizedFileURL])
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.items.first?.fileURL.standardizedFileURL.path, outputURL.standardizedFileURL.path)
    }

    // Typed all-existing with a FIFO candidate stays failed: FIFOs never verify.
    func testTypedAllExistingWithFIFOStaysFailed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fifoURL = directory.appendingPathComponent("pipe-\(UUID().uuidString).mp4")
        guard fifoURL.path.withCString({ mkfifo($0, 0o644) }) == 0 else {
            throw XCTSkip("mkfifo is not supported on this platform.")
        }
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            failureReason: .downloadAlreadyExists,
            logEntries: [],
            outputFileURLs: [fifoURL]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("No output files found after download."))
        XCTAssertTrue(viewModel.outputURLs.isEmpty)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    // Partial playlist failure remains failed with verified outputs; a failed
    // first inbox write must not prevent subsequent file registration.
    func testPartialFailureContinuesAfterFirstInboxFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = try makeExistingFile(named: "partial-a-\(UUID().uuidString).mp4", in: directory)
        let secondURL = try makeExistingFile(named: "partial-b-\(UUID().uuidString).mp4", in: directory)
        let realError = "ERROR: unable to download video data: HTTP Error 403: Forbidden"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "Download failed: \(realError)",
            failureReason: nil,
            logEntries: [JobLogEntry(message: realError)],
            outputFileURLs: [firstURL, secondURL]
        )
        let inbox = FailFirstOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/original-playlist"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        guard case let .failed(message) = viewModel.downloadState else {
            XCTFail("Expected failed for partial playlist, got \(viewModel.downloadState)")
            return
        }
        XCTAssertTrue(message.contains("Output Inbox"))
        XCTAssertNotEqual(viewModel.statusMessage, DownloaderCopy.alreadyExistsInInbox)
        XCTAssertEqual(Set(viewModel.outputURLs.map(\.standardizedFileURL.path)), Set([firstURL.standardizedFileURL.path, secondURL.standardizedFileURL.path]))
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.items.first?.fileURL.standardizedFileURL.path, secondURL.standardizedFileURL.path)
        XCTAssertEqual(inbox.items.first?.metadata["dlSourceURL"], "https://example.com/original-playlist")
    }

    // P2: completed job with no verified contained outputs must truthfully fail
    // rather than report Downloaded.
    func testCompletedWithNoVerifiedOutputsFailsInsteadOfDownloaded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .completed,
            progress: 1,
            message: "Downloaded",
            outputFileURLs: []
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        guard case let .failed(message) = viewModel.downloadState else {
            XCTFail("Expected failed when completed job has no verified outputs, got \(viewModel.downloadState)")
            return
        }
        XCTAssertEqual(message, "No output files found after download.")
        XCTAssertNotEqual(viewModel.statusMessage, "Downloaded")
        XCTAssertTrue(viewModel.outputURLs.isEmpty)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    func testCompletedWithOutsideOutputFailsInsteadOfDownloaded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outsideDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let outsideFile = try makeExistingFile(named: "outside-\(UUID().uuidString).mp4", in: outsideDir)
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .completed,
            progress: 1,
            message: "Downloaded",
            outputFileURLs: [outsideFile]
        )
        let inbox = RecordingOutputInboxStore()
        let viewModel = makeViewModel(
            outputFolder: directory,
            useCase: FakeDownloaderUseCase(job: job),
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: inbox
        )
        viewModel.urlText = "https://example.com/audio"
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { viewModel.downloadState != .downloading }
        guard case .failed = viewModel.downloadState else {
            XCTFail("Expected failed when completed outputs are outside containment, got \(viewModel.downloadState)")
            return
        }
        XCTAssertTrue(viewModel.outputURLs.isEmpty)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    func testPendingDownloadStartBlocksQuitUntilItsJobIsEnqueued() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let useCase = GatedDownloaderUseCase(runner: runner)
        let viewModel = makeViewModel(
            useCase: useCase,
            jobRunner: runner,
            outputInboxStore: RecordingOutputInboxStore(),
            jobStatusCenter: center
        )
        defer {
            for job in runner.snapshot() { runner.cancelJob(id: job.id) }
        }
        defer { useCase.release() }
        viewModel.urlText = "https://example.com/watch"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()

        // Synchronous: the pending start is registered before startDownload returns.
        XCTAssertEqual(center.quitBlockingWork.map(\.id), [ShellJobExtraSourceID.downloadStart])
        let pending = try XCTUnwrap(center.quitBlockingWork.first)
        XCTAssertFalse(pending.listed)
        XCTAssertTrue(pending.blocksQuit)
        XCTAssertEqual(pending.displayLine, "Downloading “example.com”")
        XCTAssertTrue(center.hasUnfinishedQuitBlockingWork)
        XCTAssertTrue(center.jobs.isEmpty)

        let coordinator = HubTerminationCoordinator(jobStatusCenter: center)
        let decision = coordinator.decision()
        guard case let .ask(prompt) = decision else {
            XCTFail("A pending download start must ask before quitting, got \(decision)")
            return
        }
        XCTAssertTrue(prompt.message.contains("Downloading “example.com”"), prompt.message)

        useCase.release()
        try await waitUntil { viewModel.job != nil }
        let runningJob = try XCTUnwrap(viewModel.job)
        XCTAssertTrue(center.quitBlockingWork.map(\.id).contains(runningJob.id.uuidString))
        XCTAssertFalse(center.quitBlockingWork.map(\.id).contains(ShellJobExtraSourceID.downloadStart))
    }

    func testQuitDuringPendingDownloadStartCancelsLookupAndUnregisters() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let useCase = GatedDownloaderUseCase(runner: runner)
        let viewModel = makeViewModel(
            useCase: useCase,
            jobRunner: runner,
            outputInboxStore: RecordingOutputInboxStore(),
            jobStatusCenter: center
        )
        defer { useCase.release() }
        viewModel.urlText = "https://example.com/watch"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()
        XCTAssertEqual(center.quitBlockingWork.map(\.id), [ShellJobExtraSourceID.downloadStart])

        center.cancelAllForQuit()

        try await waitUntil { center.hasUnfinishedQuitBlockingWork == false }
        XCTAssertTrue(useCase.sawCancellation)
        XCTAssertTrue(runner.snapshot().isEmpty)
        XCTAssertTrue(center.quitBlockingWork.isEmpty)
    }

    func testFailedDownloadStartUnregistersPendingEntry() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let useCase = GatedDownloaderUseCase(runner: runner, failure: .ytDlpUnavailable("x"))
        let viewModel = makeViewModel(
            useCase: useCase,
            jobRunner: runner,
            outputInboxStore: RecordingOutputInboxStore(),
            jobStatusCenter: center
        )
        defer { useCase.release() }
        viewModel.urlText = "https://example.com/watch"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()
        XCTAssertEqual(center.quitBlockingWork.map(\.id), [ShellJobExtraSourceID.downloadStart])

        useCase.release()
        try await waitUntil { viewModel.downloadState != .downloading }
        XCTAssertEqual(viewModel.downloadState, .failed("yt-dlp is required. x"))
        XCTAssertTrue(center.quitBlockingWork.isEmpty)
    }

    func testNewerStartKeepsItsPendingEntryWhenOlderStartFinishesLate() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let useCase = GatedDownloaderUseCase(runner: runner)
        let viewModel = makeViewModel(
            useCase: useCase,
            jobRunner: runner,
            outputInboxStore: RecordingOutputInboxStore(),
            jobStatusCenter: center
        )
        defer {
            for job in runner.snapshot() { runner.cancelJob(id: job.id) }
        }
        defer { useCase.release() }
        viewModel.urlText = "https://example.com/watch"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()
        XCTAssertEqual(center.quitBlockingWork.map(\.id), [ShellJobExtraSourceID.downloadStart])

        viewModel.cancelDownload()
        XCTAssertEqual(viewModel.downloadState, .canceled)
        viewModel.downloadState = .readyToDownload
        viewModel.startDownload()
        try await waitUntil { useCase.callCount == 2 }

        // Let the cancelled older start unwind; it must not clear the newer entry.
        try await waitUntil { useCase.sawCancellation }
        XCTAssertEqual(center.quitBlockingWork.map(\.id), [ShellJobExtraSourceID.downloadStart])

        useCase.release()
        try await waitUntil { viewModel.job != nil }
        XCTAssertFalse(center.quitBlockingWork.map(\.id).contains(ShellJobExtraSourceID.downloadStart))
    }

    // B-002: every configured music root stays write-protected for downloads while the
    // Vault switch is OFF. The real settings projection feeds the real view-model guard;
    // the use case is a spy that must never be reached.
    func testVaultOffRefusesArchiveOutputAndAliasBeforeEnqueue() async throws {
        let fixture = try VaultOffOutputFixture()
        defer { fixture.cleanUp() }
        let before = try fixture.archiveSnapshot()

        for destination in fixture.refusedDestinations {
            let job = Job(sourceToolID: "downloader", title: "Download")
            let useCase = FakeDownloaderUseCase(job: job)
            let jobRunner = StaticJobRunner(job: job)
            let viewModel = makeViewModel(
                settings: fixture.settings(outputFolder: destination.url),
                useCase: useCase,
                jobRunner: jobRunner,
                outputInboxStore: RecordingOutputInboxStore()
            )
            viewModel.urlText = "https://example.com/first"
            viewModel.downloadState = .readyToDownload

            viewModel.startDownload()
            try await Task.sleep(for: .milliseconds(50))

            guard case .failed(let message) = viewModel.downloadState else {
                return XCTFail("\(destination.label): expected .failed but got \(viewModel.downloadState)")
            }
            XCTAssertTrue(message.contains("music archive root"), destination.label)
            XCTAssertEqual(useCase.callCount, 0, destination.label)
            XCTAssertNil(viewModel.job, destination.label)
            XCTAssertEqual(try fixture.archiveSnapshot(), before, destination.label)
        }
    }

    func testVaultOffAdmitsOrdinaryOutputFolderNextToProtectedArchive() async throws {
        let fixture = try VaultOffOutputFixture()
        defer { fixture.cleanUp() }
        let before = try fixture.archiveSnapshot()
        let job = Job(sourceToolID: "downloader", title: "Download")
        let useCase = FakeDownloaderUseCase(job: job)
        let suiteName = "vault-off-downloader-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = makeViewModel(
            settings: fixture.settings(outputFolder: fixture.ordinaryOutput),
            useCase: useCase,
            jobRunner: StaticJobRunner(job: job),
            outputInboxStore: RecordingOutputInboxStore(),
            preferences: UserDefaultsPreferenceStore(userDefaults: defaults)
        )
        viewModel.urlText = "https://example.com/first"
        viewModel.downloadState = .readyToDownload

        viewModel.startDownload()

        XCTAssertEqual(viewModel.downloadState, .downloading)
        try await waitUntil { useCase.callCount == 1 }
        XCTAssertEqual(try fixture.archiveSnapshot(), before)
    }

    private func makeViewModel(
        settings: AppSettings? = nil,
        outputFolder: URL = URL(fileURLWithPath: "/tmp/downloader-vm"),
        useCase: any DownloaderUseCaseRunning,
        jobRunner: any JobRunning,
        outputInboxStore: any OutputInboxStore,
        jobStatusCenter: ShellJobStatusCenter? = nil,
        preferences: any PreferenceStore = InMemoryTestPreferenceStore(),
        healthChecker: YtDlpHealthChecker = YtDlpHealthChecker(),
        debounceDuration: Duration = .milliseconds(500)
    ) -> DownloaderViewModel {
        let center = jobStatusCenter ?? ShellJobStatusCenter(jobRunner: jobRunner)
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: FixtureSettingsStore(settings: settings ?? AppSettings(
                outputFolder: StoredFolderLocation(url: outputFolder),
                helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/fixture/yt-dlp"))
            )),
            preferences: preferences,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics(),
            jobStatusCenter: center
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

/// Pending-start gate: suspends `simulateAndEnqueue` until the test releases
/// it, and throws `CancellationError` when the waiting start is cancelled
/// (pane Cancel, clearInput, or quit-cancel). On release it enqueues a
/// long-running job on the real runner (or throws the injected failure).
private final class GatedDownloaderUseCase: DownloaderUseCaseRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let runner: JobRunner
    private let failure: DownloadUseCaseError?
    private var released = false
    private var waiters: [DownloadStartWaiterBox] = []
    private var storedCallCount = 0
    private var storedSawCancellation = false

    init(runner: JobRunner, failure: DownloadUseCaseError? = nil) {
        self.runner = runner
        self.failure = failure
    }

    var callCount: Int { lock.downloaderTestWithLock { storedCallCount } }
    var sawCancellation: Bool { lock.downloaderTestWithLock { storedSawCancellation } }

    func release() {
        let boxes = lock.downloaderTestWithLock { () -> [DownloadStartWaiterBox] in
            released = true
            let boxes = waiters
            waiters.removeAll()
            return boxes
        }
        for box in boxes {
            box.take()?.resume()
        }
    }

    func simulateAndEnqueue(url: URL, options: DownloadJobOptions) async throws -> Job {
        lock.downloaderTestWithLock { storedCallCount += 1 }
        do {
            try await waitForRelease()
        } catch {
            lock.downloaderTestWithLock { storedSawCancellation = true }
            throw error
        }
        if let failure {
            throw failure
        }
        return runner.enqueue(title: "Download: gated", sourceToolID: ToolFeatureID("downloader")) { _ in
            try await Task.sleep(for: .seconds(30))
        }
    }

    private func waitForRelease() async throws {
        // A start cancelled before it reaches the gate must not park at all.
        try Task.checkCancellation()
        let box = DownloadStartWaiterBox()
        let alreadyReleased = lock.downloaderTestWithLock { () -> Bool in
            if released { return true }
            waiters.append(box)
            return false
        }
        guard !alreadyReleased else { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if let alreadyCancelled = box.park(continuation) {
                    removeBox(box)
                    alreadyCancelled.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            removeBox(box)
            if let waiter = box.cancel() {
                waiter.resume(throwing: CancellationError())
            }
        }
    }

    private func removeBox(_ box: DownloadStartWaiterBox) {
        lock.downloaderTestWithLock {
            waiters.removeAll { $0 === box }
        }
    }
}

/// One parked waiter on a `GatedDownloaderUseCase` gate. The box lets the
/// task's own cancellation handler resume exactly its continuation: a bare
/// continuation cannot find itself in `onCancel`.
private final class DownloadStartWaiterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancelled = false

    /// Parks the continuation, unless already cancelled (then the caller
    /// resumes the returned continuation immediately with `CancellationError`).
    func park(_ waiter: CheckedContinuation<Void, Error>) -> CheckedContinuation<Void, Error>? {
        lock.downloaderTestWithLock {
            if cancelled {
                return waiter
            }
            continuation = waiter
            return nil
        }
    }

    /// Takes the waiter on the release path; nil when already cancelled.
    func take() -> CheckedContinuation<Void, Error>? {
        lock.downloaderTestWithLock {
            let waiter = continuation
            continuation = nil
            return waiter
        }
    }

    /// Cancels the waiter; nil when already released or never parked.
    func cancel() -> CheckedContinuation<Void, Error>? {
        lock.downloaderTestWithLock {
            cancelled = true
            let waiter = continuation
            continuation = nil
            return waiter
        }
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

private final class FailFirstOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedItems: [OutputInboxItem] = []
    private var addCount = 0

    var items: [OutputInboxItem] {
        lock.downloaderTestWithLock { storedItems }
    }

    func listItems() throws -> [OutputInboxItem] { items }

    func addItem(_ item: OutputInboxItem) throws {
        let index = lock.downloaderTestWithLock { () -> Int in
            let current = addCount
            addCount += 1
            return current
        }
        if index == 0 {
            throw FixtureOutputInboxError.forced
        }
        lock.downloaderTestWithLock {
            storedItems.append(item)
        }
    }

    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct FixtureSettingsStore: SettingsStore {
    var settings: AppSettings

    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws {}
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

private final class MutableFolderSettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var folder: URL

    init(outputFolder: URL) {
        self.folder = outputFolder
    }

    var outputFolder: URL {
        get { lock.downloaderTestWithLock { folder } }
        set { lock.downloaderTestWithLock { folder = newValue } }
    }

    func loadSettings() throws -> AppSettings {
        AppSettings(
            outputFolder: StoredFolderLocation(url: outputFolder),
            helperTools: HelperToolSettings(ytDlp: URL(fileURLWithPath: "/fixture/yt-dlp"))
        )
    }

    func saveSettings(_ settings: AppSettings) throws {}
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        var current = try loadSettings()
        update(&current)
        outputFolder = current.outputFolder.url
    }
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

/// In-memory preferences so download tests never read or write `UserDefaults.standard`
/// (`startDownload` persists the format selection).
private final class InMemoryTestPreferenceStore: PreferenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var bools: [String: Bool] = [:]
    private var datas: [String: Data] = [:]
    private var strings: [String: String] = [:]

    func bool(forKey key: String) -> Bool? { lock.withLock { bools[key] } }
    func set(_ value: Bool, forKey key: String) { lock.withLock { bools[key] = value } }
    func data(forKey key: String) -> Data? { lock.withLock { datas[key] } }
    func set(_ data: Data, forKey key: String) { lock.withLock { datas[key] = data } }
    func string(forKey key: String) -> String? { lock.withLock { strings[key] } }
    func set(_ value: String, forKey key: String) { lock.withLock { strings[key] = value } }
    func removeObject(forKey key: String) {
        lock.withLock {
            bools.removeValue(forKey: key)
            datas.removeValue(forKey: key)
            strings.removeValue(forKey: key)
        }
    }
}
