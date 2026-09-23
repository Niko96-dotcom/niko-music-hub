import AVFoundation
import AppCore
import FeatureAudioConverter
import XCTest

/// The shell jobs-row "Cancel" must stop the conversion now — not after the file in flight.
@MainActor
final class AudioConverterCancelTests: XCTestCase {
    func testJobsRowCancelStopsInFlightFFmpegConversionAndKeepsFinishedFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputFolder = directory.appendingPathComponent("out", isDirectory: true)

        let first = directory.appendingPathComponent("First.wav")
        let second = directory.appendingPathComponent("Second.wav")
        let third = directory.appendingPathComponent("Third.wav")
        for url in [first, second, third] {
            try writeTestWAV(to: url, bitDepth: 16)
        }

        let secondStarted = Flag()
        // Behaves like `FoundationExternalProcessRunner`: a long FFmpeg run that only ends
        // early when its Task is canceled (the real runner then kills the process group).
        let runner = CancellableFakeRunner { request in
            let outputURL = URL(fileURLWithPath: request.arguments.last ?? "")
            if request.arguments.contains(second.path) {
                try Data("half-written".utf8).write(to: outputURL)
                secondStarted.set()
                try await Task.sleep(for: .seconds(3))
            }
            try writeTestWAV(to: outputURL, bitDepth: 24)
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let inbox = RecordingInboxStore()
        let context = makeContext(outputFolder: outputFolder, inbox: inbox)
        let viewModel = AudioConverterViewModel(
            context: context,
            batchUseCase: BatchAudioConversionUseCase(
                settingsStore: context.settingsStore,
                outputInboxStore: inbox,
                converterFactory: { _ in
                    FFmpegAudioConverter(
                        ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
                        runner: runner
                    )
                }
            )
        )
        viewModel.addFileURLs([first, second, third])

        viewModel.startConversion()
        try await waitUntil(seconds: 2) { secondStarted.isSet }
        XCTAssertTrue(context.jobStatusCenter.jobs.contains { $0.id == ShellJobExtraSourceID.converter })
        XCTAssertTrue(ShellJobStatusCopy.converterCancelHelp.hasPrefix("Stops converting now"))

        context.jobStatusCenter.cancel(id: ShellJobExtraSourceID.converter)

        try await waitUntil(seconds: 1) { !viewModel.isConverting }
        XCTAssertFalse(viewModel.isConverting, "Cancel must not wait for the file in flight to finish")
        XCTAssertEqual(viewModel.rows.map(\.state), [.verified, .skipped, .skipped])
        XCTAssertEqual(viewModel.rows.map(\.statusText), [
            AudioConverterCopy.verified,
            AudioConverterCopy.canceled,
            AudioConverterCopy.canceled
        ])
        XCTAssertEqual(viewModel.statusText, "Canceled — 1 of 3 files converted")
        XCTAssertFalse(viewModel.canRequestStopAfterCurrent)
        XCTAssertTrue(viewModel.canConvertToWAV == false)
        XCTAssertTrue(context.jobStatusCenter.jobs.isEmpty)
        XCTAssertEqual(runner.requests.count, 2, "The third file must never start")

        let outputs = try FileManager.default.contentsOfDirectory(atPath: outputFolder.path)
        XCTAssertEqual(outputs, ["First - 44100Hz 24bit.wav"], "No half-written temp output may remain")
        XCTAssertEqual(inbox.items.map(\.fileURL.lastPathComponent), ["First - 44100Hz 24bit.wav"])
        let keptURL = try XCTUnwrap(viewModel.rows[0].outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
    }

    func testCanceledFFmpegRunWithRealProcessRunnerStopsPromptlyAndLeavesNoTempFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Long.wav")
        let outputFolder = directory.appendingPathComponent("out", isDirectory: true)
        try writeTestWAV(to: source, bitDepth: 16)
        // Stand-in "ffmpeg": starts the temp output, then keeps running like a long file.
        let fakeFFmpeg = directory.appendingPathComponent("ffmpeg")
        try """
        #!/bin/sh
        for last in "$@"; do :; done
        echo $$ > "\(directory.path)/pid"
        printf 'partial' > "$last"
        exec sleep 30
        """.write(to: fakeFFmpeg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeFFmpeg.path)

        let converter = FFmpegAudioConverter(ffmpegURL: fakeFFmpeg)
        let request = ConversionRequest(
            sourceURL: source,
            outputDirectory: outputFolder,
            preset: .cubaseDefault,
            sourceType: .wav
        )
        let task = Task.detached { try await converter.convert(request) }
        try await waitUntil(seconds: 5) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path)) ?? []
            return names.contains { $0.hasSuffix(".tmp.wav") }
        }

        let started = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A canceled FFmpeg conversion must not produce a WAV")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        let outputs = (try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path)) ?? []
        XCTAssertEqual(outputs, [])

        let pidText = try String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)
        let pid = try XCTUnwrap(pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        try await waitUntil(seconds: 2) { kill(pid, 0) != 0 }
        XCTAssertNotEqual(kill(pid, 0), 0, "The canceled FFmpeg process must be terminated")
    }

    func testNativeConverterStopsWhenItsTaskIsCanceled() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Long.wav")
        let outputFolder = directory.appendingPathComponent("out", isDirectory: true)
        try writeTestWAV(to: source, bitDepth: 16, frameCount: 44_100)
        let request = ConversionRequest(
            sourceURL: source,
            outputDirectory: outputFolder,
            preset: .cubaseDefault,
            sourceType: .wav
        )

        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeAudioConverter().convert(request)
        }

        do {
            _ = try await task.value
            XCTFail("A canceled native conversion must not produce a WAV")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
        let outputs = (try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path)) ?? []
        XCTAssertEqual(outputs, [], "Canceled native conversion must leave no temp output")
    }

    func testPipelineDoesNotFallBackToFFmpegAfterCancellation() async throws {
        let factoryCalls = Flag()
        let pipeline = AudioConversionPipeline(
            native: ThrowingConverter(error: CancellationError()),
            helperSettings: HelperToolSettings(),
            ffmpegConverterFactory: { _ in
                factoryCalls.set()
                return ThrowingConverter(error: AudioConversionError.conversionFailed("unused"))
            }
        )
        let request = ConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/Canceled.flac"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            preset: .cubaseDefault,
            sourceType: .flac
        )

        do {
            _ = try await pipeline.convert(request)
            XCTFail("Cancellation must propagate")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
        XCTAssertFalse(factoryCalls.isSet)
    }

    private func makeContext(outputFolder: URL, inbox: RecordingInboxStore) -> ToolContext {
        ToolContext(
            registeredToolCount: 1,
            settingsStore: InMemorySettingsStore(
                settings: AppSettings(outputFolder: StoredFolderLocation(url: outputFolder))
            ),
            outputInboxStore: inbox,
            jobRunner: IdleJobRunner(),
            fileActions: NoFileActions(),
            diagnostics: SilentDiagnostics()
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NMHConverterCancelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(seconds: Double, _ predicate: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out after \(seconds)s")
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

private final class CancellableFakeRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (ExternalProcessRequest) async throws -> ExternalProcessResult
    private var storedRequests: [ExternalProcessRequest] = []

    var requests: [ExternalProcessRequest] { lock.withLock { storedRequests } }

    init(handler: @escaping @Sendable (ExternalProcessRequest) async throws -> ExternalProcessResult) {
        self.handler = handler
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { storedRequests.append(request) }
        return try await handler(request)
    }
}

private struct ThrowingConverter: AudioConverting {
    let error: any Error
    func convert(_ request: ConversionRequest) async throws -> ConversionResult { throw error }
}

private final class RecordingInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [OutputInboxItem] = []
    var items: [OutputInboxItem] { lock.withLock { stored } }
    func listItems() throws -> [OutputInboxItem] { items }
    func addItem(_ item: OutputInboxItem) throws { lock.withLock { stored.append(item) } }
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    var settings: AppSettings
    init(settings: AppSettings) { self.settings = settings }
    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws { self.settings = settings }
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws { update(&settings) }
}

private struct IdleJobRunner: JobRunning {
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

private func writeTestWAV(to url: URL, bitDepth: Int, frameCount: AVAudioFrameCount = 512) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: bitDepth,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
        throw CocoaError(.fileWriteUnknown)
    }
    buffer.frameLength = frameCount
    if let channels = buffer.floatChannelData {
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(frameCount) {
                channels[channel][frame] = Float(frame % 32) / 32.0
            }
        }
    }
    try file.write(from: buffer)
}
