import AVFoundation
import AppCore
import FeatureAudioConverter
import XCTest

final class FFmpegAudioConverterTests: XCTestCase {
    func testBuildsSafeArgumentsForTwentyFourBitWAV() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Source File.wav")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try writeTestWAV(to: sourceURL, sampleRate: 44100, bitDepth: 16, channelCount: 2)

        let runner = RecordingRunner { request in
            try writeTestWAV(
                to: URL(fileURLWithPath: request.arguments.last ?? ""),
                sampleRate: 44100,
                bitDepth: 24,
                channelCount: 2
            )
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let converter = FFmpegAudioConverter(ffmpegURL: ffmpegURL, runner: runner)

        let result = try await converter.convert(
            ConversionRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                preset: .cubaseDefault,
                sourceType: .wav
            )
        )

        let request = try XCTUnwrap(runner.requests.first)
        XCTAssertEqual(request.executableURL, ffmpegURL)
        XCTAssertEqual(
            request.arguments,
            [
                "-hide_banner",
                "-nostdin",
                "-y",
                "-i",
                sourceURL.path,
                "-vn",
                "-ar",
                "44100",
                "-ac",
                "2",
                "-c:a",
                "pcm_s24le",
                request.arguments.last ?? ""
            ]
        )
        XCTAssertTrue((request.arguments.last ?? "").hasSuffix(".tmp.wav"))
        XCTAssertEqual(result.converterPath, .ffmpeg)
        XCTAssertEqual(result.spec, WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2))
        XCTAssertEqual(result.outputURL.lastPathComponent, "Source File - 44100Hz 24bit.wav")
    }

    func testUsesSixteenBitPCMCodec() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Source File.wav")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try writeTestWAV(to: sourceURL, sampleRate: 44100, bitDepth: 16, channelCount: 1)
        var preset = AudioPreset.cubaseDefault
        preset.bitDepth = 16

        let runner = RecordingRunner { request in
            try writeTestWAV(
                to: URL(fileURLWithPath: request.arguments.last ?? ""),
                sampleRate: 44100,
                bitDepth: 16,
                channelCount: 1
            )
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let converter = FFmpegAudioConverter(
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            runner: runner
        )

        _ = try await converter.convert(
            ConversionRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                preset: preset,
                sourceType: .wav
            )
        )

        XCTAssertEqual(runner.requests.first?.arguments.dropLast().last, "pcm_s16le")
    }

    func testNonZeroExitThrowsConversionError() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Broken.mp3")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try Data("source".utf8).write(to: sourceURL)
        let converter = FFmpegAudioConverter(
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            runner: RecordingRunner { _ in
                ExternalProcessResult(exitCode: 2, standardOutput: "", standardError: "decode failed")
            }
        )
        var preset = AudioPreset.cubaseDefault
        preset.channelMode = .stereo

        do {
            _ = try await converter.convert(
                ConversionRequest(
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory,
                    preset: preset,
                    sourceType: .mp3
                )
            )
            XCTFail("Expected FFmpeg failure")
        } catch let error as AudioConversionError {
            XCTAssertEqual(
                error,
                .conversionFailed("FFmpeg exited with code 2: decode failed")
            )
        }
    }

    func testVerificationCallAfterSuccessMovesFinalOutput() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Verified.m4a")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try Data("source".utf8).write(to: sourceURL)
        let runner = RecordingRunner { request in
            try writeTestWAV(
                to: URL(fileURLWithPath: request.arguments.last ?? ""),
                sampleRate: 44100,
                bitDepth: 24,
                channelCount: 2
            )
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let converter = FFmpegAudioConverter(
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            runner: runner
        )
        var preset = AudioPreset.cubaseDefault
        preset.channelMode = .stereo

        let result = try await converter.convert(
            ConversionRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                preset: preset,
                sourceType: .m4a
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertFalse(try outputDirectoryContainsTemporaryWAV(outputDirectory))
    }

    func testRemovesTemporaryFileOnVerificationFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Mismatch.m4a")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try Data("source".utf8).write(to: sourceURL)
        let converter = FFmpegAudioConverter(
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            runner: RecordingRunner { request in
                try writeTestWAV(
                    to: URL(fileURLWithPath: request.arguments.last ?? ""),
                    sampleRate: 48000,
                    bitDepth: 16,
                    channelCount: 2
                )
                return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            }
        )
        var preset = AudioPreset.cubaseDefault
        preset.channelMode = .stereo

        do {
            _ = try await converter.convert(
                ConversionRequest(
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory,
                    preset: preset,
                    sourceType: .m4a
                )
            )
            XCTFail("Expected verification failure")
        } catch {
            XCTAssertFalse(try outputDirectoryContainsTemporaryWAV(outputDirectory))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: outputDirectory
                        .appendingPathComponent("Mismatch - 44100Hz 24bit.wav")
                        .path
                )
            )
        }
    }

    func testUnsupportedBitDepthThrowsConversionError() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Unsupported.m4a")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try Data("source".utf8).write(to: sourceURL)
        var preset = AudioPreset.cubaseDefault
        preset.bitDepth = 32
        preset.channelMode = .stereo
        let converter = FFmpegAudioConverter(
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            runner: RecordingRunner { _ in
                XCTFail("Unsupported bit depth should fail before process launch")
                return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
            }
        )

        do {
            _ = try await converter.convert(
                ConversionRequest(
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory,
                    preset: preset,
                    sourceType: .m4a
                )
            )
            XCTFail("Expected unsupported bit depth")
        } catch let error as AudioConversionError {
            XCTAssertEqual(error, .unsupportedBitDepth(32))
        }
    }

    func testPreserveMonoStereoProbesFFmpegWhenNativeCannotReadSource() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Mono Source.mp3")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try Data("source".utf8).write(to: sourceURL)
        let runner = RecordingRunner { request in
            if request.arguments.last == sourceURL.path {
                return ExternalProcessResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "Input #0, mp3, from 'Mono Source.mp3':\n  Stream #0:0: Audio: mp3, 44100 Hz, mono, fltp"
                )
            }

            try writeTestWAV(
                to: URL(fileURLWithPath: request.arguments.last ?? ""),
                sampleRate: 44100,
                bitDepth: 24,
                channelCount: 1
            )
            return ExternalProcessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let converter = FFmpegAudioConverter(
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            runner: runner
        )

        let result = try await converter.convert(
            ConversionRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                preset: .cubaseDefault,
                sourceType: .mp3
            )
        )

        XCTAssertEqual(runner.requests.count, 2)
        XCTAssertEqual(runner.requests[0].arguments, ["-hide_banner", "-nostdin", "-i", sourceURL.path])
        let channelArgumentIndex = try XCTUnwrap(runner.requests[1].arguments.firstIndex(of: "-ac"))
        XCTAssertEqual(runner.requests[1].arguments[channelArgumentIndex + 1], "1")
        XCTAssertEqual(result.spec.channelCount, 1)
    }

    func testNoShellInvocationAppearsInSource() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureAudioConverter/FFmpegAudioConverter.swift",
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("\"/bin/sh\""))
        XCTAssertFalse(source.contains("\"sh\", \"-c\""))
        XCTAssertFalse(source.contains("shell"))
    }

    private func outputDirectoryContainsTemporaryWAV(_ outputDirectory: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: outputDirectory.path) else {
            return false
        }

        return try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )
        .contains { $0.lastPathComponent.hasSuffix(".tmp.wav") }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingRunner: ExternalProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (ExternalProcessRequest) throws -> ExternalProcessResult
    private var storedRequests: [ExternalProcessRequest] = []

    var requests: [ExternalProcessRequest] {
        lock.withLock { storedRequests }
    }

    init(handler: @escaping @Sendable (ExternalProcessRequest) throws -> ExternalProcessResult) {
        self.handler = handler
    }

    func run(_ request: ExternalProcessRequest) async throws -> ExternalProcessResult {
        lock.withLock {
            storedRequests.append(request)
        }
        return try handler(request)
    }
}

private func writeTestWAV(
    to url: URL,
    sampleRate: Int,
    bitDepth: Int,
    channelCount: AVAudioChannelCount
) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: Double(sampleRate),
        AVNumberOfChannelsKey: Int(channelCount),
        AVLinearPCMBitDepthKey: bitDepth,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let frameCount: AVAudioFrameCount = 512
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: frameCount
    ) else {
        XCTFail("Could not create test WAV buffer")
        return
    }

    buffer.frameLength = frameCount
    fill(buffer)
    try file.write(from: buffer)
}

private func fill(_ buffer: AVAudioPCMBuffer) {
    let frameLength = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)

    if let channels = buffer.floatChannelData {
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                channels[channel][frame] = Float(frame % 32) / 32.0
            }
        }
    } else if let channels = buffer.int16ChannelData {
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                channels[channel][frame] = Int16(frame % Int(Int16.max))
            }
        }
    } else if let channels = buffer.int32ChannelData {
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                channels[channel][frame] = Int32(frame % Int(Int16.max))
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
