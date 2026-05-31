import AVFAudio
import AppCore
import XCTest
@testable import FeatureAudioRecorder

final class WAVRecorderWriterTests: XCTestCase {
    func testWAVWriterCreatesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_writer_\(UUID().uuidString).wav")

        let writer = try WAVRecorderWriter(outputURL: outputURL, preset: .cubaseDefault)
        XCTAssertTrue(writer.isRecording)

        let result = try writer.finalize()
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(result.sampleRate, 44100)
        XCTAssertEqual(result.bitDepth, 24)
        XCTAssertEqual(result.channelCount, 2)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testWAVWriterHasCorrectSampleRate() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_samplerate_\(UUID().uuidString).wav")

        let writer = try WAVRecorderWriter(outputURL: outputURL, preset: .cubaseDefault)
        _ = try writer.finalize()

        let audioFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(audioFile.fileFormat.sampleRate, 44100)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testWAVWriterHasCorrectBitDepth() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_bitdepth_\(UUID().uuidString).wav")

        let writer = try WAVRecorderWriter(outputURL: outputURL, preset: .cubaseDefault)
        _ = try writer.finalize()

        let audioFile = try AVAudioFile(forReading: outputURL)
        let bitsPerChannel = audioFile.fileFormat.streamDescription.pointee.mBitsPerChannel
        XCTAssertEqual(Int(bitsPerChannel), 24)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testWAVWriterHasCorrectChannelCount() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_channels_\(UUID().uuidString).wav")

        let writer = try WAVRecorderWriter(outputURL: outputURL, preset: .cubaseDefault)
        _ = try writer.finalize()

        let audioFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(audioFile.fileFormat.channelCount, 2)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testWAVWriterAcceptsProcessingFormatBuffer() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_processing_buffer_\(UUID().uuidString).wav")

        let writer = try WAVRecorderWriter(outputURL: outputURL, preset: .cubaseDefault)
        let format = writer.processingFormat
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        buffer.frameLength = 1_024

        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    channelData[channel][frame] = Float(frame % 64) / 64.0
                }
            }
        }

        try writer.writeBuffer(buffer)
        let result = try writer.finalize()

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(fileSize, 4_096)
        XCTAssertEqual(result.frameCount, 1_024)

        let audioFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(audioFile.fileFormat.sampleRate, 44_100)
        XCTAssertEqual(Int(audioFile.fileFormat.streamDescription.pointee.mBitsPerChannel), 24)
        XCTAssertEqual(audioFile.length, 1_024)

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testCaptureFormatResolverUsesAggregateSampleRate() throws {
        let tapFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))

        let resolved = RecorderCaptureFormatResolver.resolve(
            tapFormat: tapFormat,
            aggregateNominalSampleRate: 44_100
        )

        XCTAssertEqual(resolved.sampleRate, 44_100)
        XCTAssertEqual(resolved.channelCount, 2)
        XCTAssertEqual(resolved.commonFormat, tapFormat.commonFormat)
        XCTAssertEqual(resolved.isInterleaved, tapFormat.isInterleaved)
    }

    func testCaptureFormatResolverKeepsTapRateWhenAggregateRateMatches() throws {
        let tapFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 2,
            interleaved: false
        ))

        let resolved = RecorderCaptureFormatResolver.resolve(
            tapFormat: tapFormat,
            aggregateNominalSampleRate: 44_100
        )

        XCTAssertTrue(resolved === tapFormat)
    }

    func testRecorderDiagnosticsSummaryIncludesCaptureAndOutputRates() {
        let diagnostics = RecorderDiagnostics(
            outputDeviceUID: "device",
            tapSampleRate: 48_000,
            tapChannelCount: 2,
            captureSampleRate: 44_100,
            outputSampleRate: 44_100
        )

        XCTAssertTrue(diagnostics.summary.contains("tap=48000Hz/2ch"))
        XCTAssertTrue(diagnostics.summary.contains("capture=44100Hz"))
        XCTAssertTrue(diagnostics.summary.contains("output=44100Hz"))
    }

    func testFilenameOverride() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let filename = useCase.generateOutputFilename(override: "My Recording.wav")
        XCTAssertEqual(filename, "My Recording.wav")
    }

    func testFilenameAutoTimestamp() throws {
        let useCase = RecordSystemAudioUseCase(capturePort: MockAudioCapturePort())
        let filename = useCase.generateOutputFilename(override: nil)
        XCTAssertTrue(filename.hasPrefix("Recording "))
        XCTAssertTrue(filename.hasSuffix(".wav"))
    }
}

private final class MockAudioCapturePort: AudioCapturePort, @unchecked Sendable {
    var recording: Bool = false

    func checkPermission() async -> RecorderPermissionState {
        .authorized
    }

    func requestPermission() async -> RecorderPermissionState {
        .authorized
    }

    func isCompatibleMacOS() -> Bool {
        true
    }

    func startRecording(outputURL: URL, preset: AudioPreset, maxDuration: TimeInterval?) async throws -> AsyncStream<RecorderAudioLevel> {
        AsyncStream { _ in }
    }

    func stopRecording() async throws -> RecorderResult {
        RecorderResult(outputURL: URL(fileURLWithPath: "/tmp/test.wav"), duration: 0, sampleRate: 44100, bitDepth: 24, channelCount: 2)
    }
}
