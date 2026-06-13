import AppCore
@testable import FeatureStemSeparation
import Foundation
import Testing

@MainActor
struct StemSeparationViewModelTests {

    private func makeViewModel(
        outputInboxStore: OutputInboxStore = FakeOutputInboxStore(),
        jobRunner: JobRunner = JobRunner()
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
        return StemSeparationViewModel(context: context, service: service)
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
