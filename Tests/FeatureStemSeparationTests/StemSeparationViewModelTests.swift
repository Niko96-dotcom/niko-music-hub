import AppCore
@testable import FeatureStemSeparation
import Foundation
import Testing

@MainActor
struct StemSeparationViewModelTests {

    private func makeViewModel(
        outputInboxStore: OutputInboxStore = FakeOutputInboxStore(),
        jobRunner: JobRunner = JobRunner(),
        youtubeWorkflow: YouTubeStemSeparationWorkflow? = nil
    ) -> StemSeparationViewModel {
        let context = ToolContext(
            registeredToolCount: 7,
            settingsStore: FakeSettingsStore(),
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner,
            fileActions: FixtureFileActions(),
            diagnostics: FakeDiagnostics()
        )
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: outputInboxStore,
            jobRunner: jobRunner
        )
        return StemSeparationViewModel(context: context, service: service, youtubeWorkflow: youtubeWorkflow)
    }

    @Test
    func init_defaultsToQualityPreset() {
        let vm = makeViewModel()

        #expect(vm.selectedPreset == .best4)
    }

    @Test
    func handleDrop_setsDroppedFileURLForAudioFile() {
        let vm = makeViewModel()
        let url = URL(fileURLWithPath: "/Users/music/song.wav")
        #expect(vm.handleDrop(urls: [url]) == true)
        #expect(vm.droppedFileURL == url)
    }

    @Test
    func handleDrop_rejectsNonAudioFile() {
        let vm = makeViewModel()
        let url = URL(fileURLWithPath: "/Users/music/song.txt")
        #expect(vm.handleDrop(urls: [url]) == false)
        #expect(vm.errorMessage != nil)
    }

    @Test
    func canAcceptDrop_isFalseForTxtAndTrueForWav() {
        let vm = makeViewModel()
        let txt = URL(fileURLWithPath: "/Users/music/song.txt")
        let wav = URL(fileURLWithPath: "/Users/music/song.wav")
        #expect(vm.canAcceptDrop(urls: [txt]) == false)
        #expect(vm.canAcceptDrop(urls: [wav]) == true)
    }

    @Test
    func testStartSeparationUsesLatestHelperPath() async throws {
        let settingsStore = FakeSettingsStore()
        #expect(settingsStore.stored.helperTools.demucsMlx == nil)

        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("nmh-065-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }

        let fixtureAudio = scratch.appendingPathComponent("fixture.wav")
        fileManager.createFile(atPath: fixtureAudio.path, contents: Data("RIFF".utf8))
        let helperURL = scratch.appendingPathComponent("demucs-mlx")
        fileManager.createFile(atPath: helperURL.path, contents: Data())
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        let outputRoot = scratch.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let inbox = FakeOutputInboxStore()
        let jobRunner = JobRunner()
        let processRunner = StubStemProcessRunner()
        let backend = DemucsMLXBackend(
            runner: processRunner,
            settingsProvider: {
                (try? settingsStore.loadSettings().helperTools) ?? HelperToolSettings()
            }
        )
        let service = StemSeparationService(
            backend: backend,
            outputInboxStore: inbox,
            jobRunner: jobRunner
        )
        let context = ToolContext(
            registeredToolCount: 7,
            settingsStore: settingsStore,
            outputInboxStore: inbox,
            jobRunner: jobRunner,
            fileActions: FixtureFileActions(),
            diagnostics: FakeDiagnostics()
        )
        let vm = StemSeparationViewModel(context: context, service: service)
        #expect(backend.configuredDemucsURL == nil)

        _ = vm.handleDrop(urls: [fixtureAudio])
        try settingsStore.updateSettings { settings in
            settings.helperTools.demucsMlx = helperURL
            settings.outputFolder = StoredFolderLocation(url: outputRoot)
        }

        vm.startSeparation()

        for _ in 0..<200 where vm.isRunning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(vm.outputFolderURL == outputRoot)
        #expect(backend.configuredDemucsURL == helperURL)
        #expect(processRunner.lastExecutableURL == helperURL)
    }

    @Test
    func startSeparation_enqueuesJobAndObservesProgress() async throws {
        let vm = makeViewModel()
        let url = URL(fileURLWithPath: "/Users/music/song.wav")
        _ = vm.handleDrop(urls: [url])

        vm.startSeparation()

        #expect(vm.isRunning == true)
        #expect(vm.currentJobID != nil)

        // Wait for completion
        while vm.isRunning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(vm.results.count == 4)
    }

    @Test
    func startYouTubeSeparation_requiresYouTubeURL() {
        let vm = makeViewModel()
        vm.youtubeURLText = "https://example.com/song"

        vm.startYouTubeSeparation()

        #expect(vm.errorMessage == "Paste a valid YouTube URL.")
        #expect(vm.isRunning == false)
    }

    @Test
    func youtubeURLValidationRejectsDeceptiveHosts() {
        #expect(StemSeparationViewModel.isApprovedYouTubeHost("youtube.com"))
        #expect(StemSeparationViewModel.isApprovedYouTubeHost("music.youtube.com"))
        #expect(StemSeparationViewModel.isApprovedYouTubeHost("youtu.be"))
        #expect(!StemSeparationViewModel.isApprovedYouTubeHost("notyoutube.com"))
        #expect(!StemSeparationViewModel.isApprovedYouTubeHost("youtube.com.evil.example"))
        #expect(!StemSeparationViewModel.isApprovedYouTubeHost("evilyoutu.be"))
    }

    @Test
    func startYouTubeSeparation_enqueuesWorkflowJob() async throws {
        let runner = JobRunner()
        let inbox = FakeOutputInboxStore()
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])
        let service = StemSeparationService(backend: backend, outputInboxStore: inbox, jobRunner: runner)
        let workflow = YouTubeStemSeparationWorkflow(
            downloader: FakeViewModelYouTubeAudioDownloader(),
            stemService: service,
            jobRunner: runner
        )
        let vm = makeViewModel(outputInboxStore: inbox, jobRunner: runner, youtubeWorkflow: workflow)
        vm.youtubeURLText = "https://youtu.be/test"

        vm.startYouTubeSeparation()

        #expect(vm.isRunning == true)
        #expect(vm.currentJobID != nil)

        while vm.isRunning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(vm.results.count == 4)
    }

    @Test
    func cancelSeparation_stopsRunningJob() async throws {
        let vm = makeViewModel()
        let url = URL(fileURLWithPath: "/Users/music/song.wav")
        _ = vm.handleDrop(urls: [url])

        vm.startSeparation()
        let id = vm.currentJobID
        #expect(id != nil)

        vm.cancelSeparation()

        while vm.isRunning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(vm.statusMessage.contains("Canceled") || vm.errorMessage != nil || vm.statusMessage.contains("complete"))
    }

    @Test
    func loadResults_filtersByToolID() throws {
        let inbox = FakeOutputInboxStore()
        let stemItem = OutputInboxItem(
            fileURL: URL(fileURLWithPath: "/out/vocals.wav"),
            sourceToolID: StemSeparationService.toolID,
            status: .available,
            metadata: ["role": "vocals"]
        )
        let otherItem = OutputInboxItem(
            fileURL: URL(fileURLWithPath: "/out/song.wav"),
            sourceToolID: "wav-converter",
            status: .available
        )
        try inbox.addItem(stemItem)
        try inbox.addItem(otherItem)

        let vm = makeViewModel(outputInboxStore: inbox)
        vm.loadResults()

        #expect(vm.results.count == 1)
        #expect(vm.results.first?.id == stemItem.id)
    }

    @Test
    func testIntakeWellAccessibilityLabelIsDeclared() throws {
        let stemSource = try String(
            contentsOfFile: "Sources/FeatureStemSeparation/StemSeparationView.swift",
            encoding: .utf8
        )
        #expect(stemSource.contains("Drop an audio file or choose a file to separate"))
        #expect(stemSource.contains(".accessibilityElement(children: .combine)"))

        let converterSource = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )
        #expect(converterSource.contains("Drop audio files to convert"))
    }

    @Test
    func loadResults_sortsByCreatedAtDescending() throws {
        let inbox = FakeOutputInboxStore()
        let older = OutputInboxItem(
            fileURL: URL(fileURLWithPath: "/out/older.wav"),
            sourceToolID: StemSeparationService.toolID,
            status: .available
        )
        let newer = OutputInboxItem(
            fileURL: URL(fileURLWithPath: "/out/newer.wav"),
            sourceToolID: StemSeparationService.toolID,
            status: .available
        )
        try inbox.addItem(older)
        try inbox.addItem(newer)

        let vm = makeViewModel(outputInboxStore: inbox)
        vm.loadResults()

        #expect(vm.results.first?.id == newer.id)
    }

    @Test
    func canStart_isFalseWhileHelperNeedsSetup() async throws {
        let emptyLocator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [],
            isExecutable: { _ in false }
        )
        let settingsStore = FakeSettingsStore()
        let inbox = FakeOutputInboxStore()
        let jobRunner = JobRunner()
        let context = ToolContext(
            registeredToolCount: 7,
            settingsStore: settingsStore,
            outputInboxStore: inbox,
            jobRunner: jobRunner,
            fileActions: FixtureFileActions(),
            diagnostics: FakeDiagnostics()
        )
        let backend = MockStemSeparationBackend()
        backend.filesToWrite = [(.vocals, "vocals.wav"), (.drums, "drums.wav"), (.bass, "bass.wav"), (.other, "other.wav")]
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])
        let service = StemSeparationService(backend: backend, outputInboxStore: inbox, jobRunner: jobRunner)
        let vm = StemSeparationViewModel(
            context: context,
            service: service,
            healthChecker: DemucsMLXHealthChecker(locator: emptyLocator)
        )
        _ = vm.handleDrop(urls: [URL(fileURLWithPath: "/Users/music/song.wav")])
        #expect(vm.canStart == true)
        vm.refreshHelperHealth()
        for _ in 0..<100 where vm.helperNeedsSetup == false && vm.errorMessage == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(vm.helperNeedsSetup == true)
        #expect(vm.canStart == false)
        #expect(vm.errorMessage == StemSeparationHelperCopy.missingBody)
    }

    @Test
    func unusableHealth_setsDiagnosticInsteadOfMissingSentence() async throws {
        let executable = URL(fileURLWithPath: "/fixture/bin/demucs-mlx")
        let fixtureLocator = HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [executable.deletingLastPathComponent()],
            isExecutable: { $0 == executable.path }
        )
        struct FailingRunner: ExternalProcessRunning {
            func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
                .init(exitCode: 1, standardOutput: "", standardError: "boom line1\nline2")
            }
        }
        let settingsStore = FakeSettingsStore()
        let inbox = FakeOutputInboxStore()
        let jobRunner = JobRunner()
        let context = ToolContext(
            registeredToolCount: 7,
            settingsStore: settingsStore,
            outputInboxStore: inbox,
            jobRunner: jobRunner,
            fileActions: FixtureFileActions(),
            diagnostics: FakeDiagnostics()
        )
        let backend = MockStemSeparationBackend()
        backend.requestedResult = .success(outputFolderURL: URL(fileURLWithPath: "/unused"), stems: [])
        let service = StemSeparationService(backend: backend, outputInboxStore: inbox, jobRunner: jobRunner)
        let vm = StemSeparationViewModel(
            context: context,
            service: service,
            healthChecker: DemucsMLXHealthChecker(runner: FailingRunner(), locator: fixtureLocator)
        )
        vm.refreshHelperHealth()
        for _ in 0..<100 where vm.helperNeedsSetup == false {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(vm.helperNeedsSetup == true)
        #expect(vm.errorMessage == "demucs-mlx could not start: boom line1")
    }
}

private final class FakeSettingsStore: SettingsStore, @unchecked Sendable {
    var stored: AppSettings = .default

    func loadSettings() throws -> AppSettings { stored }
    func saveSettings(_ settings: AppSettings) throws { stored = settings }
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        var settings = stored
        update(&settings)
        stored = settings
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

private struct FakeDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}

private final class StubStemProcessRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedExecutableURL: URL?

    var lastExecutableURL: URL? { lock.withLock { recordedExecutableURL } }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { recordedExecutableURL = request.executableURL }
        return ExternalProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "stubbed"
        )
    }
}

private struct FakeViewModelYouTubeAudioDownloader: YouTubeAudioDownloading {
    func downloadAudio(
        from sourceURL: URL,
        to outputDirectory: URL,
        progress: JobProgress
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("downloaded.wav")
        FileManager.default.createFile(atPath: outputURL.path, contents: Data("audio".utf8))
        progress.update(progress: 1, message: "Downloaded")
        return outputURL
    }
}
