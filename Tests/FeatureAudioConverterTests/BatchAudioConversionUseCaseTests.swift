import AppCore
import FeatureAudioConverter
import XCTest

final class BatchAudioConversionUseCaseTests: XCTestCase {
    func testMissingFFmpegAffectsOnlyOneRow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingHelperFile = makeBatchFile(named: "Needs Helper.flac", type: .flac, in: directory)
        let nativeFile = makeBatchFile(named: "Native.wav", type: .wav, in: directory)
        let inbox = RecordingOutputInboxStore()
        let converter = RecordingBatchConverter { request in
            if request.sourceURL == missingHelperFile.sourceURL {
                throw AudioConversionError.missingFFmpeg(
                    message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
                )
            }
            return makeResult(for: request, converterPath: .native)
        }
        let useCase = makeUseCase(directory: directory, inbox: inbox, converter: converter)

        let outcomes = try await useCase.convert(
            files: [missingHelperFile, nativeFile],
            stopController: StopAfterCurrentController()
        )

        XCTAssertEqual(converter.requests.map(\.sourceURL), [missingHelperFile.sourceURL, nativeFile.sourceURL])
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes[0].status, .failed(message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."))
        guard case .verified = outcomes[1].status else {
            return XCTFail("Expected native file to continue and verify")
        }
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.items.first?.metadata["converter"], "Native")
    }

    func testStopAfterCurrentSkipsRemainingRows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = makeBatchFile(named: "First.wav", type: .wav, in: directory)
        let second = makeBatchFile(named: "Second.wav", type: .wav, in: directory)
        let third = makeBatchFile(named: "Third.wav", type: .wav, in: directory)
        let controller = StopAfterCurrentController()
        let converter = RecordingBatchConverter { request in
            controller.requestStopAfterCurrent()
            return makeResult(for: request, converterPath: .native)
        }
        let useCase = makeUseCase(
            directory: directory,
            inbox: RecordingOutputInboxStore(),
            converter: converter
        )

        let outcomes = try await useCase.convert(
            files: [first, second, third],
            stopController: controller
        )

        XCTAssertEqual(converter.requests.map(\.sourceURL), [first.sourceURL])
        guard case .verified = outcomes[0].status else {
            return XCTFail("Expected active row to finish before stopping")
        }
        XCTAssertEqual(outcomes[1].status, .skipped)
        XCTAssertEqual(outcomes[2].status, .skipped)
    }

    func testOnlyVerifiedOutputsAreAddedToInbox() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let verified = makeBatchFile(named: "Verified.m4a", type: .m4a, in: directory)
        let failed = makeBatchFile(named: "Failed.mp3", type: .mp3, in: directory)
        let unverified = makeBatchFile(named: "Unverified.wav", type: .wav, in: directory)
        let inbox = RecordingOutputInboxStore()
        let converter = RecordingBatchConverter { request in
            switch request.sourceURL {
            case verified.sourceURL:
                return makeResult(for: request, converterPath: .ffmpeg, channelCount: 1)
            case failed.sourceURL:
                throw AudioConversionError.conversionFailed("decode failed")
            default:
                throw AudioConversionError.verificationFailed("metadata mismatch")
            }
        }
        let useCase = makeUseCase(directory: directory, inbox: inbox, converter: converter)

        _ = try await useCase.convert(
            files: [verified, failed, unverified],
            stopController: StopAfterCurrentController()
        )

        XCTAssertEqual(inbox.items.count, 1)
        let item = try XCTUnwrap(inbox.items.first)
        XCTAssertEqual(item.status, .available)
        XCTAssertEqual(item.sourceToolID, "wav-converter")
        XCTAssertEqual(item.metadata["sourceFile"], verified.sourceURL.path)
        XCTAssertEqual(item.metadata["sampleRate"], "44100")
        XCTAssertEqual(item.metadata["bitDepth"], "24")
        XCTAssertEqual(item.metadata["channels"], "1")
        XCTAssertEqual(item.metadata["converter"], "FFmpeg")
        XCTAssertEqual(item.metadata["sourceType"], "m4a")
    }

    private func makeUseCase(
        directory: URL,
        inbox: RecordingOutputInboxStore,
        converter: RecordingBatchConverter
    ) -> BatchAudioConversionUseCase {
        BatchAudioConversionUseCase(
            settingsStore: FixtureSettingsStore(
                settings: AppSettings(outputFolder: StoredFolderLocation(url: directory))
            ),
            outputInboxStore: inbox,
            converterFactory: { _ in converter }
        )
    }

    private func makeBatchFile(
        named name: String,
        type: SupportedAudioFileType,
        in directory: URL
    ) -> BatchAudioConversionFile {
        BatchAudioConversionFile(
            sourceURL: directory.appendingPathComponent(name, isDirectory: false),
            sourceType: type
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NikoMusicHubBatchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private func makeResult(
    for request: ConversionRequest,
    converterPath: AudioConverterPath,
    channelCount: Int = 2
) -> ConversionResult {
    ConversionResult(
        sourceURL: request.sourceURL,
        outputURL: request.outputDirectory
            .appendingPathComponent(request.sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("wav"),
        spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: channelCount),
        converterPath: converterPath
    )
}

private struct FixtureSettingsStore: SettingsStore {
    var settings: AppSettings

    func loadSettings() throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

private final class RecordingOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedItems: [OutputInboxItem] = []

    var items: [OutputInboxItem] {
        lock.withLock { storedItems }
    }

    func listItems() throws -> [OutputInboxItem] {
        items
    }

    func addItem(_ item: OutputInboxItem) throws {
        lock.withLock {
            storedItems.append(item)
        }
    }

    func updateItem(_ item: OutputInboxItem) throws {}

    func refreshAvailability() throws {}
}

private final class RecordingBatchConverter: AudioConverting, @unchecked Sendable {
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
