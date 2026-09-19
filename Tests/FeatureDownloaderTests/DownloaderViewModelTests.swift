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

    // D1: marker alone must not claim completed. Only a verified existing
    // regular file within the output root may register.
    func testAlreadyDownloadedWithValidExistingFileRegistersInInbox() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = try makeExistingFile(named: "existing-\(UUID().uuidString).mp4", in: directory)
        let marker = "[download] \(outputURL.path) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            logEntries: [JobLogEntry(message: marker)]
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
        let marker = "[download] \(missing.path) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            logEntries: [JobLogEntry(message: marker)]
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
        let marker = "[download] \(subdir.path) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            logEntries: [JobLogEntry(message: marker)]
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
        let marker = "[download] \(outsideFile.path) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            logEntries: [JobLogEntry(message: marker)]
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
        let escapePath = linkURL.appendingPathComponent(outsideFile.lastPathComponent).path
        let marker = "[download] \(escapePath) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            logEntries: [JobLogEntry(message: marker)]
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
        let marker = "[download] \(outputURL.path) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            logEntries: [JobLogEntry(message: marker)]
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

    // D1: captured destination must survive a settings mutation during a queued
    // download. Relative marker resolves beneath the captured directory only;
    // a same-name file appearing in the mutated directory must not verify.
    func testSettingsMutationDuringJobUsesCapturedOutputDirectory() async throws {
        let originalDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: originalDir) }
        let mutatedDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: mutatedDir) }
        let fileName = "shared-\(UUID().uuidString).mp4"
        // Only the mutated directory contains the same-name file.
        _ = try makeExistingFile(named: fileName, in: mutatedDir)
        let marker = "[download] \(fileName) has already been downloaded"
        let job = Job(
            sourceToolID: "downloader",
            title: "Download",
            state: .failed,
            message: "No output files found after download.",
            logEntries: [JobLogEntry(message: marker)]
        )
        let inbox = RecordingOutputInboxStore()
        let store = MutableFolderSettingsStore(outputFolder: originalDir)
        let useCase = FakeDownloaderUseCase(job: job, delay: .milliseconds(30))
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: store,
            preferences: UserDefaultsPreferenceStore(),
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

    // D1: an earlier playlist marker plus a later real error must not convert
    // to success. Contract: expose the verified existing output AND propagate
    // the actual failure.
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
            logEntries: [JobLogEntry(message: marker), JobLogEntry(message: realError)]
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

    // D1: stall without ERROR: plus an earlier already marker must stay failed
    // while still exposing verified files. Never infer success from absence of
    // the ERROR: substring.
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
            logEntries: [JobLogEntry(message: marker)]
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
        XCTAssertFalse(DownloaderViewModel.isExplicitSkipOutcome(logEntries: [marker], message: stallMessage))
    }

    // D1: generic non-ERROR download failure plus marker must stay failed while
    // exposing verified files.
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
            logEntries: [JobLogEntry(message: marker), JobLogEntry(message: failureMessage)]
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

    // D1: positive skip classification — pure output-not-found outcome stays a
    // successful skip; any other message stays failed.
    func testExplicitSkipOutcomeRequiresOutputNotFoundMessage() {
        let marker = "[download] /tmp/out/a.mp4 has already been downloaded"
        XCTAssertTrue(DownloaderViewModel.isExplicitSkipOutcome(
            logEntries: [marker],
            message: "No output files found after download."
        ))
        XCTAssertFalse(DownloaderViewModel.isExplicitSkipOutcome(
            logEntries: [marker],
            message: "Download failed: \(DownloadStallMonitor.stallErrorMessage)"
        ))
        XCTAssertFalse(DownloaderViewModel.isExplicitSkipOutcome(
            logEntries: [marker],
            message: "Download failed: connection reset by peer"
        ))
        XCTAssertFalse(DownloaderViewModel.isExplicitSkipOutcome(
            logEntries: [marker, "ERROR: unable to download video data"],
            message: "No output files found after download."
        ))
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
