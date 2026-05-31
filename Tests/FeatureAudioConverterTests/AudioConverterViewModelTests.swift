import AppCore
import FeatureAudioConverter
import XCTest

@MainActor
final class AudioConverterViewModelTests: XCTestCase {
    func testQueuedAndUnsupportedRowsAreCreatedFromScanner() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let audio = try makeFile(named: "Loop.m4a", in: directory)
        let text = try makeFile(named: "Notes.txt", in: directory)
        let viewModel = makeViewModel(outputFolder: directory)

        viewModel.addFileURLs([audio, text])

        XCTAssertEqual(viewModel.rows.map(\.state), [.queued, .unsupported])
        XCTAssertEqual(viewModel.rows[0].statusText, "Ready for WAV conversion")
        XCTAssertEqual(
            viewModel.rows[1].statusText,
            "This file type is not supported in Phase 3. Add M4A, MP3, WAV, AIFF, or FLAC instead."
        )
        XCTAssertEqual(viewModel.rows[0].plannedOutputName, "Loop - 44100Hz 24bit.wav")
    }

    func testConvertButtonDisabledWithoutQueuedRows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let unsupported = try makeFile(named: "Notes.txt", in: directory)
        let viewModel = makeViewModel(outputFolder: directory)

        XCTAssertFalse(viewModel.canConvertToWAV)
        viewModel.addFileURLs([unsupported])

        XCTAssertFalse(viewModel.canConvertToWAV)
    }

    func testMissingHelperCopyMatchesUISpec() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Needs Helper.mp3", in: directory)
        let converter = RecordingViewModelConverter { _ in
            throw AudioConversionError.missingFFmpeg(
                message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
            )
        }
        let viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([source])

        _ = await viewModel.convertQueuedRows()

        XCTAssertEqual(viewModel.rows.first?.state, .failed)
        XCTAssertEqual(
            viewModel.rows.first?.statusText,
            "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
        )
        XCTAssertEqual(viewModel.rows.first?.recoveryActionTitle, "Choose FFmpeg")
    }

    func testChooseFFmpegPersistsHelperAndRequeuesRow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Needs Helper.mp3", in: directory)
        let ffmpegURL = try makeFile(named: "ffmpeg", in: directory)
        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let converter = RecordingViewModelConverter { _ in
            throw AudioConversionError.missingFFmpeg(
                message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
            )
        }
        let healthChecker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(
                    exitCode: 0,
                    standardOutput: "ffmpeg version 8.1",
                    standardError: ""
                )
            )),
            fileExists: { $0 == ffmpegURL.path }
        )
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            settingsStore: settingsStore,
            ffmpegHealthChecker: healthChecker
        )
        viewModel.addFileURLs([source])
        _ = await viewModel.convertQueuedRows()
        let rowID = try XCTUnwrap(viewModel.rows.first?.id)

        await viewModel.chooseFFmpegAndRetry(rowID: rowID, ffmpegURL: ffmpegURL)

        XCTAssertEqual(settingsStore.settings.helperTools.ffmpeg, ffmpegURL)
        XCTAssertEqual(viewModel.rows.first?.state, .queued)
        XCTAssertNil(viewModel.rows.first?.recoveryActionTitle)
    }

    func testChooseFFmpegKeepsRowFailedWhenHelperIsUnusable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Needs Helper.mp3", in: directory)
        let ffmpegURL = try makeFile(named: "ffmpeg", in: directory)
        let converter = RecordingViewModelConverter { _ in
            throw AudioConversionError.missingFFmpeg(
                message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
            )
        }
        let healthChecker = FFmpegHealthChecker(
            runner: FakeExternalProcessRunner(result: .success(
                ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "bad helper")
            )),
            fileExists: { $0 == ffmpegURL.path }
        )
        let viewModel = makeViewModel(
            outputFolder: directory,
            converter: converter,
            ffmpegHealthChecker: healthChecker
        )
        viewModel.addFileURLs([source])
        _ = await viewModel.convertQueuedRows()
        let rowID = try XCTUnwrap(viewModel.rows.first?.id)

        await viewModel.chooseFFmpegAndRetry(rowID: rowID, ffmpegURL: ffmpegURL)

        XCTAssertEqual(viewModel.rows.first?.state, .failed)
        XCTAssertEqual(viewModel.rows.first?.recoveryActionTitle, "Choose FFmpeg")
        XCTAssertEqual(viewModel.rows.first?.statusText, "Selected FFmpeg could not be used: bad helper")
    }

    func testStopAfterCurrentStateHandoff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try makeFile(named: "First.wav", in: directory)
        let second = try makeFile(named: "Second.wav", in: directory)
        var viewModel: AudioConverterViewModel!
        let converter = RecordingViewModelConverter { request in
            if request.sourceURL == first {
                await MainActor.run {
                    viewModel.requestStopAfterCurrent()
                }
            }
            return makeResult(for: request)
        }
        viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([first, second])

        _ = await viewModel.convertQueuedRows()

        XCTAssertEqual(viewModel.rows.map(\.state), [.verified, .skipped])
        XCTAssertEqual(converter.requests.map(\.sourceURL), [first])
    }

    func testEditingWAVPresetPersistsAndUpdatesPresetSummary() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let settingsStore = FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
        )
        let viewModel = makeViewModel(outputFolder: directory, settingsStore: settingsStore)

        XCTAssertEqual(viewModel.currentAudioPreset, .cubaseDefault)
        XCTAssertEqual(viewModel.presetSummaryText, "44.1 kHz - 24-bit - Preserve mono/stereo")

        viewModel.updateWAVPreset(sampleRate: 48000, bitDepth: 16, channelMode: .mono)

        XCTAssertEqual(settingsStore.settings.audioPreset.sampleRate, 48000)
        XCTAssertEqual(settingsStore.settings.audioPreset.bitDepth, 16)
        XCTAssertEqual(settingsStore.settings.audioPreset.channelMode, .mono)
        XCTAssertEqual(settingsStore.settings.audioPreset.channelCount, 1)
        XCTAssertEqual(viewModel.currentAudioPreset, settingsStore.settings.audioPreset)
        XCTAssertEqual(viewModel.presetSummaryText, "48 kHz - 16-bit - Mono")

        viewModel.updateWAVPreset(sampleRate: 96000, bitDepth: 24, channelMode: .stereo)

        XCTAssertEqual(settingsStore.settings.audioPreset.channelCount, 2)
        XCTAssertEqual(viewModel.presetSummaryText, "96 kHz - 24-bit - Stereo")
    }

    func testEditingWAVPresetRefreshesQueuedOutputNames() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let viewModel = makeViewModel(outputFolder: directory)
        viewModel.addFileURLs([source])

        XCTAssertEqual(viewModel.rows.first?.plannedOutputName, "Loop - 44100Hz 24bit.wav")

        viewModel.updateWAVPreset(sampleRate: 48000, bitDepth: 16, channelMode: .mono)

        XCTAssertEqual(viewModel.rows.first?.plannedOutputName, "Loop - 48000Hz 16bit.wav")
    }

    func testConversionUsesEditedWAVPreset() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try makeFile(named: "Loop.m4a", in: directory)
        let converter = RecordingViewModelConverter { request in
            makeResult(for: request)
        }
        let viewModel = makeViewModel(outputFolder: directory, converter: converter)
        viewModel.addFileURLs([source])

        viewModel.updateWAVPreset(sampleRate: 88200, bitDepth: 32, channelMode: .stereo)
        _ = await viewModel.convertQueuedRows()

        XCTAssertEqual(converter.requests.first?.preset.sampleRate, 88200)
        XCTAssertEqual(converter.requests.first?.preset.bitDepth, 32)
        XCTAssertEqual(converter.requests.first?.preset.channelMode, .stereo)
        XCTAssertEqual(converter.requests.first?.preset.channelCount, 2)
    }

    func testAudioConverterViewContainsUISpecCopy() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )

        [
            "WAV Converter",
            "Drop audio files to convert",
            "Choose Files",
            "Add Files",
            "Convert",
            "Stop",
            "viewModel.presetSummaryText",
            "Ready for WAV conversion",
            "Verified WAV ready",
            "Choose FFmpeg",
            "Reveal in Finder"
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing copy: \($0)")
        }
    }

    func testAudioConverterViewContainsEditablePresetControls() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )

        [
            "Edit Preset",
            "Picker(\"Sample rate\"",
            "Picker(\"Bit depth\"",
            "Picker(\"Channel handling\"",
            "viewModel.presetSummaryText",
            "updateWAVPreset(sampleRate:"
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing preset control source: \($0)")
        }

        XCTAssertFalse(source.contains("Text(\"44.1 kHz - 24-bit - Preserve mono/stereo\")"))
    }

    func testAudioConverterViewExcludesOutOfScopeFeatureCopy() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/AudioConverterView.swift",
            encoding: .utf8
        )
        let forbiddenPattern = "trim|fade|loudness|key analysis|downloader|recording|recursive"

        XCTAssertNil(
            source.range(of: forbiddenPattern, options: [.regularExpression, .caseInsensitive])
        )
    }

    private func makeViewModel(
        outputFolder: URL,
        converter: RecordingViewModelConverter = RecordingViewModelConverter { request in
            makeResult(for: request)
        },
        settingsStore: FixtureSettingsStore? = nil,
        ffmpegHealthChecker: FFmpegHealthChecker = FFmpegHealthChecker()
    ) -> AudioConverterViewModel {
        let settingsStore = settingsStore ?? FixtureSettingsStore(
            settings: AppSettings(outputFolder: StoredFolderLocation(url: outputFolder))
        )
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: settingsStore,
            outputInboxStore: FixtureOutputInboxStore(),
            jobRunner: FixtureJobRunner(),
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics()
        )
        return AudioConverterViewModel(
            context: context,
            batchUseCase: BatchAudioConversionUseCase(
                settingsStore: context.settingsStore,
                outputInboxStore: context.outputInboxStore,
                converterFactory: { _ in converter }
            ),
            ffmpegHealthChecker: ffmpegHealthChecker
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try Data("fixture".utf8).write(to: url)
        return url
    }
}

private func makeResult(for request: ConversionRequest) -> ConversionResult {
    ConversionResult(
        sourceURL: request.sourceURL,
        outputURL: request.outputDirectory
            .appendingPathComponent(request.sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("wav"),
        spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2),
        converterPath: .native
    )
}

private final class FixtureSettingsStore: SettingsStore, @unchecked Sendable {
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func loadSettings() throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        self.settings = settings
    }

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        update(&settings)
    }
}

private struct FixtureOutputInboxStore: OutputInboxStore {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {}
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct FixtureJobRunner: JobRunning {
    func listJobs() -> [Job] { [] }
    func job(id: Job.ID) -> Job? { nil }
    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        Job(sourceToolID: sourceToolID, title: title)
    }
    func cancelJob(id: Job.ID) {}
}

private struct FixtureFileActions: FileActions {
    @MainActor
    func chooseOutputFolder() -> URL? { nil }

    @MainActor
    func chooseDirectory(prompt: String) -> URL? { nil }

    @MainActor
    func chooseExecutable(prompt: String) -> URL? { nil }

    @MainActor
    func revealInFinder(_ url: URL) {}
}

private struct FixtureDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}

private struct FakeExternalProcessRunner: ExternalProcessRunning {
    var result: Result<ExternalProcessResult, Error>

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try result.get()
    }
}

private final class RecordingViewModelConverter: AudioConverting, @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (ConversionRequest) async throws -> ConversionResult
    private var storedRequests: [ConversionRequest] = []

    var requests: [ConversionRequest] {
        lock.withLock { storedRequests }
    }

    init(handler: @escaping @Sendable (ConversionRequest) async throws -> ConversionResult) {
        self.handler = handler
    }

    func convert(_ request: ConversionRequest) async throws -> ConversionResult {
        lock.withLock {
            storedRequests.append(request)
        }
        return try await handler(request)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
