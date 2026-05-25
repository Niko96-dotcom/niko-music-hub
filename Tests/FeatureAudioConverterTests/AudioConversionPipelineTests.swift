import AppCore
import FeatureAudioConverter
import XCTest

final class AudioConversionPipelineTests: XCTestCase {
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
                ))
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
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
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
                fileExists: { _ in true }
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

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
