import AppCore
import AVFoundation
import Combine
@testable import FeatureArchiveBrowser
@testable import FeatureAudioRecorder
import NikoMusicCore
import XCTest

/// The recorder and the archive preview share one recording signal, the context's.
/// Both sides are built by their own production wiring: the recorder by
/// `AudioRecorderFeature.makeViewModel(context:capturePort:)` with a fake capture
/// port instead of CoreAudio, the archive by `ArchiveBrowserViewModel(context:)`.
@MainActor
final class AudioCaptureActivityWiringTests: XCTestCase {
    func testRecordingInTheRecorderPausesArchivePreview() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-wiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = try Self.makeSong(in: folder)
        let context = Self.makeContext(outputFolder: folder.appendingPathComponent("Takes", isDirectory: true))
        let archive = ArchiveBrowserViewModel(context: context)
        let session = archive.previewSession
        defer { session.clear() }

        archive.audition(song)
        try await Self.waitUntilLoaded(session.player)
        XCTAssertTrue(session.isPlaying)

        let recorder = AudioRecorderFeature.makeViewModel(context: context, capturePort: TakeUntilStoppedCapturePort())
        let recording = expectation(description: "the take is recording")
        let observation = recorder.$recordingState.sink { if $0 == .recording { recording.fulfill() } }
        defer { observation.cancel() }
        await recorder.startRecording()
        await fulfillment(of: [recording], timeout: 2)

        XCTAssertTrue(session.captureActive, "The archive must see the recorder's take")
        XCTAssertFalse(session.isPlaying, "A take pauses the playing preview")
        session.toggle()
        XCTAssertFalse(session.isPlaying, "Play does nothing while the take records")

        await recorder.stopRecording()
        XCTAssertEqual(recorder.recordingState, .idle)
        XCTAssertFalse(session.captureActive)
        XCTAssertFalse(session.isPlaying, "The preview never resumes by itself")
        session.toggle()
        XCTAssertTrue(session.isPlaying, "Play works again after the take")
    }

    // MARK: - Fixtures

    private static func makeContext(outputFolder: URL) -> ToolContext {
        ToolContext(
            settingsStore: FixedSettingsStore(settings: AppSettings(outputFolder: StoredFolderLocation(url: outputFolder))),
            preferences: InMemoryPreferenceStore(),
            outputInboxStore: EmptyOutputInboxStore(),
            jobRunner: JobRunner(),
            fileActions: NoFileActions(),
            diagnostics: SilentDiagnostics(),
            processRunner: FoundationExternalProcessRunner(processGroups: LiveProcessGroupRegistry())
        )
    }

    /// A song with one 3-second silent mix, enough for the preview player to load and play.
    private static func makeSong(in folder: URL) throws -> Song {
        let url = folder.appendingPathComponent("mix.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3 * 8000))
        buffer.frameLength = buffer.frameCapacity
        if let samples = buffer.floatChannelData?[0] { samples.initialize(repeating: 0, count: Int(buffer.frameLength)) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        let preview = PreviewCandidate(filePath: url, fileName: url.lastPathComponent, folderRole: .mixdown,
                                       modifiedAt: Date(), detectedRole: .mainMix)
        return Song(folderPath: folder, originalFolderName: "Fixture", displayTitle: "Fixture",
                    previewCandidates: [preview], mainPreviewCandidateID: preview.id)
    }

    private static func waitUntilLoaded(_ player: ArchivePreviewPlayer) async throws {
        let deadline = Date().addingTimeInterval(6)
        while player.isLoading, player.playbackError == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(player.playbackError)
        XCTAssertFalse(player.isLoading)
    }
}

/// Grants permission and records until stopped; writes no file. Stopping ends the
/// take as cancelled, so the recorder returns to idle and saves nothing.
private final class TakeUntilStoppedCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool { false }
    func checkPermission() async -> RecorderPermissionState { .authorized }
    func requestPermission() async -> RecorderPermissionState { .authorized }
    func isCompatibleMacOS() -> Bool { true }
    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { _ in }
    }
    func stopRecording() async throws -> RecorderResult { throw CancellationError() }
}

private struct FixedSettingsStore: SettingsStore {
    let settings: AppSettings
    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws {}
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

private struct EmptyOutputInboxStore: OutputInboxStore {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {}
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct NoFileActions: FileActions {
    @MainActor func chooseOutputFolder() -> URL? { nil }
    @MainActor func chooseDirectory(prompt: String) -> URL? { nil }
    @MainActor func chooseExecutable(prompt: String) -> URL? { nil }
    @MainActor func chooseAudioFile(prompt: String) -> URL? { nil }
    @MainActor func revealInFinder(_ url: URL) {}
}

private struct SilentDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}
