import AppCore
import FeatureAudioConverter
import XCTest

final class AudioConversionPipelineTests: XCTestCase {
    private func locator(executables: Set<String>) -> HelperToolLocator {
        HelperToolLocator(
            managedRoot: URL(fileURLWithPath: "/nonexistent-managed"),
            systemDirectories: [URL(fileURLWithPath: "/fixture/bin", isDirectory: true)],
            isExecutable: { executables.contains($0) }
        )
    }

    func testReturnsNativeResultWithoutCallingFFmpeg() async throws {
        let request = makeRequest(sourceName: "Native.wav")
        let nativeResult = ConversionResult(
            sourceURL: request.sourceURL,
            outputURL: request.outputDirectory.appendingPathComponent("Native - 44100Hz 24bit.wav"),
            spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2),
            converterPath: .native
        )
        let native = FakeAudioConverter(result: .success(nativeResult))
        let factory = RecordingFFmpegFactory(
            converter: FakeAudioConverter(result: .failure(AudioConversionError.conversionFailed("unused")))
        )
        let pipeline = makePipeline(native: native, factory: factory)

        let result = try await pipeline.convert(request)

        XCTAssertEqual(result, nativeResult)
        XCTAssertEqual(native.convertCallCount, 1)
        XCTAssertEqual(factory.callCount, 0)
    }

    func testFallsBackToFFmpegAfterNativeUnsupported() async throws {
        let request = makeRequest(sourceName: "Fallback.flac", sourceType: .flac)
        let ffmpegResult = ConversionResult(
            sourceURL: request.sourceURL,
            outputURL: request.outputDirectory.appendingPathComponent("Fallback - 44100Hz 24bit.wav"),
            spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2),
            converterPath: .ffmpeg
        )
        let native = FakeAudioConverter(result: .failure(AudioConversionError.unsupportedSourceType(request.sourceURL)))
        let ffmpeg = FakeAudioConverter(result: .success(ffmpegResult))
        let factory = RecordingFFmpegFactory(converter: ffmpeg)
        let pipeline = makePipeline(native: native, factory: factory)

        let result = try await pipeline.convert(request)

        XCTAssertEqual(result, ffmpegResult)
        XCTAssertEqual(native.convertCallCount, 1)
        XCTAssertEqual(factory.callCount, 1)
        XCTAssertEqual(ffmpeg.convertCallCount, 1)
    }

    func testFallsBackToFFmpegUsingAutoDetectedPathWhenSettingsUnset() async throws {
        let request = makeRequest(sourceName: "Auto FFmpeg.flac", sourceType: .flac)
        let detectedURL = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let ffmpegResult = ConversionResult(
            sourceURL: request.sourceURL,
            outputURL: request.outputDirectory.appendingPathComponent("Auto FFmpeg - 44100Hz 24bit.wav"),
            spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2),
            converterPath: .ffmpeg
        )
        let native = FakeAudioConverter(result: .failure(AudioConversionError.unsupportedSourceType(request.sourceURL)))
        let factory = RecordingFFmpegFactory(converter: FakeAudioConverter(result: .success(ffmpegResult)))
        let pipeline = AudioConversionPipeline(
            native: native,
            helperSettings: HelperToolSettings(ffmpeg: nil),
            ffmpegConverterFactory: factory.makeConverter,
            healthChecker: FFmpegHealthChecker(
                runner: FakeExternalProcessRunner(result: .success(
                    ExternalProcessResult(
                        exitCode: 0,
                        standardOutput: "ffmpeg version 8.1",
                        standardError: ""
                    )
                )),
                locator: locator(executables: [detectedURL.path])
            )
        )

        let result = try await pipeline.convert(request)

        XCTAssertEqual(result, ffmpegResult)
        XCTAssertEqual(factory.callCount, 1)
        XCTAssertEqual(factory.resolvedURLs, [detectedURL])
    }

    func testFFmpegHealthCheckedAtMostOnceAcrossFiles() async throws {
        let runner = CountingHealthRunner()
        let fixtureURL = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        let checker = FFmpegHealthChecker(
            runner: runner,
            locator: locator(executables: [fixtureURL.path])
        )
        let ffmpegResult = ConversionResult(
            sourceURL: makeRequest(sourceName: "A.flac", sourceType: .flac).sourceURL,
            outputURL: URL(fileURLWithPath: "/tmp/out/A.wav"),
            spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2),
            converterPath: .ffmpeg
        )
        let factory = RecordingFFmpegFactory(converter: FakeAudioConverter(result: .success(ffmpegResult)))
        let pipeline = AudioConversionPipeline(
            native: FakeAudioConverter(result: .failure(AudioConversionError.unsupportedSourceType(URL(fileURLWithPath: "/tmp/x")))),
            helperSettings: HelperToolSettings(ffmpeg: nil),
            ffmpegConverterFactory: factory.makeConverter,
            healthChecker: checker
        )
        for name in ["A.flac", "B.flac", "C.flac"] {
            _ = try await pipeline.convert(makeRequest(sourceName: name, sourceType: .flac))
        }
        XCTAssertEqual(runner.runCount, 1)
        XCTAssertEqual(factory.callCount, 3)
    }

    func testFailedHealthCheckIsNotCachedSoLaterFileCanRetry() async throws {
        let runner = FlakyHealthRunner()
        let fixtureURL = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        // First call fails (missing), second succeeds. Locator always resolves.
        let checker = FFmpegHealthChecker(
            runner: runner,
            locator: locator(executables: [fixtureURL.path])
        )
        let ffmpegResult = ConversionResult(
            sourceURL: URL(fileURLWithPath: "/tmp/A.flac"),
            outputURL: URL(fileURLWithPath: "/tmp/out/A.wav"),
            spec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2),
            converterPath: .ffmpeg
        )
        let factory = RecordingFFmpegFactory(converter: FakeAudioConverter(result: .success(ffmpegResult)))
        let pipeline = AudioConversionPipeline(
            native: FakeAudioConverter(result: .failure(AudioConversionError.unsupportedSourceType(URL(fileURLWithPath: "/tmp/x")))),
            helperSettings: HelperToolSettings(ffmpeg: nil),
            ffmpegConverterFactory: factory.makeConverter,
            healthChecker: checker
        )
        do {
            _ = try await pipeline.convert(makeRequest(sourceName: "A.flac", sourceType: .flac))
            XCTFail("Expected FFmpeg unavailable")
        } catch let error as AudioConversionError {
            guard case .conversionFailed = error else {
                XCTFail("Expected conversionFailed, got \(error)")
                return
            }
        }
        runner.shouldSucceed = true
        _ = try await pipeline.convert(makeRequest(sourceName: "B.flac", sourceType: .flac))
        XCTAssertEqual(runner.runCount, 2)
        XCTAssertEqual(factory.callCount, 1)
    }

    func testMissingFFmpegProducesRecoverableMessage() async throws {
        let request = makeRequest(sourceName: "Needs FFmpeg.mp3", sourceType: .mp3)
        let native = FakeAudioConverter(result: .failure(AudioConversionError.conversionFailed("native failed")))
        let pipeline = AudioConversionPipeline(
            native: native,
            helperSettings: HelperToolSettings(ffmpeg: nil),
            ffmpegConverterFactory: nil,
            healthChecker: FFmpegHealthChecker(
                runner: FakeExternalProcessRunner(result: .success(
                    ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
                )),
                locator: locator(executables: [])
            )
        )

        do {
            _ = try await pipeline.convert(request)
            XCTFail("Expected missing FFmpeg error")
        } catch let error as AudioConversionError {
            XCTAssertEqual(
                error,
                .missingFFmpeg(
                    message: "FFmpeg is required for this file. Choose FFmpeg, then convert this file again."
                )
            )
        }
    }

    func testFallbackResultStillUsesVerifiedOutputSpec() async throws {
        let request = makeRequest(sourceName: "Verified Fallback.aiff", sourceType: .aiff)
        let verifiedSpec = WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 1)
        let native = FakeAudioConverter(result: .failure(AudioConversionError.verificationFailed("native mismatch")))
        let ffmpegResult = ConversionResult(
            sourceURL: request.sourceURL,
            outputURL: request.outputDirectory.appendingPathComponent("Verified Fallback - 44100Hz 24bit.wav"),
            spec: verifiedSpec,
            converterPath: .ffmpeg
        )
        let factory = RecordingFFmpegFactory(converter: FakeAudioConverter(result: .success(ffmpegResult)))
        let pipeline = makePipeline(native: native, factory: factory)

        let result = try await pipeline.convert(request)

        XCTAssertEqual(result.converterPath, .ffmpeg)
        XCTAssertEqual(result.spec, verifiedSpec)
    }

    private func makePipeline(
        native: FakeAudioConverter,
        factory: RecordingFFmpegFactory
    ) -> AudioConversionPipeline {
        let ffmpegURL = URL(fileURLWithPath: "/fixture/bin/ffmpeg")
        return AudioConversionPipeline(
            native: native,
            helperSettings: HelperToolSettings(ffmpeg: ffmpegURL),
            ffmpegConverterFactory: factory.makeConverter,
            healthChecker: FFmpegHealthChecker(
                runner: FakeExternalProcessRunner(result: .success(
                    ExternalProcessResult(
                        exitCode: 0,
                        standardOutput: "ffmpeg version 8.1",
                        standardError: ""
                    )
                )),
                locator: locator(executables: [ffmpegURL.path])
            )
        )
    }

    private func makeRequest(
        sourceName: String,
        sourceType: SupportedAudioFileType = .wav
    ) -> ConversionRequest {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubPipelineTests", isDirectory: true)
        return ConversionRequest(
            sourceURL: directory.appendingPathComponent(sourceName),
            outputDirectory: directory.appendingPathComponent("out", isDirectory: true),
            preset: .cubaseDefault,
            sourceType: sourceType
        )
    }
}

private final class FakeAudioConverter: AudioConverting, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<ConversionResult, Error>
    private var storedRequests: [ConversionRequest] = []

    var convertCallCount: Int {
        lock.withLock { storedRequests.count }
    }

    init(result: Result<ConversionResult, Error>) {
        self.result = result
    }

    func convert(_ request: ConversionRequest) async throws -> ConversionResult {
        lock.withLock {
            storedRequests.append(request)
        }
        return try result.get()
    }
}

private final class RecordingFFmpegFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: any AudioConverting
    private var urls: [URL] = []

    var callCount: Int {
        lock.withLock { urls.count }
    }

    var resolvedURLs: [URL] {
        lock.withLock { urls }
    }

    init(converter: any AudioConverting) {
        self.converter = converter
    }

    func makeConverter(ffmpegURL: URL) -> any AudioConverting {
        lock.withLock {
            urls.append(ffmpegURL)
        }
        return converter
    }
}

private struct FakeExternalProcessRunner: ExternalProcessRunning {
    var result: Result<ExternalProcessResult, Error>

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        try result.get()
    }
}

private final class CountingHealthRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var runCount: Int { lock.withLock { count } }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { count += 1 }
        XCTAssertEqual(request.timeoutSeconds, 15)
        return ExternalProcessResult(exitCode: 0, standardOutput: "ffmpeg version 8.1", standardError: "")
    }
}

private final class FlakyHealthRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var succeed = false

    var shouldSucceed: Bool {
        get { lock.withLock { succeed } }
        set { lock.withLock { succeed = newValue } }
    }

    var runCount: Int { lock.withLock { count } }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock { count += 1 }
        let shouldSucceed: Bool = lock.withLock { self.succeed }
        if shouldSucceed {
            return ExternalProcessResult(exitCode: 0, standardOutput: "ffmpeg version 8.1", standardError: "")
        }
        return ExternalProcessResult(exitCode: 1, standardOutput: "", standardError: "missing")
    }
}
