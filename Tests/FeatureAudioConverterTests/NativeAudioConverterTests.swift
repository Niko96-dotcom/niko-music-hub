import AVFoundation
import AppCore
import FeatureAudioConverter
import XCTest

final class NativeAudioConverterTests: XCTestCase {
    func testConvertsGeneratedWAVWithNativePath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Short Source.wav")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try writeTestWAV(
            to: sourceURL,
            sampleRate: 48000,
            bitDepth: 16,
            channelCount: 2
        )

        let converter = NativeAudioConverter()
        let result = try await converter.convert(
            ConversionRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                preset: .cubaseDefault,
                sourceType: .wav
            )
        )

        XCTAssertEqual(result.converterPath, .native)
        XCTAssertEqual(result.spec, WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertEqual(result.outputURL.lastPathComponent, "Short Source - 44100Hz 24bit.wav")
        XCTAssertFalse(try outputDirectoryContainsTemporaryWAV(outputDirectory))
    }

    func testRemovesTemporaryFileOnFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Short Source.wav")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try writeTestWAV(
            to: sourceURL,
            sampleRate: 48000,
            bitDepth: 16,
            channelCount: 2
        )

        let converter = NativeAudioConverter(
            verifier: WAVOutputVerifier(fileExists: { _ in false })
        )

        do {
            _ = try await converter.convert(
                ConversionRequest(
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory,
                    preset: .cubaseDefault,
                    sourceType: .wav
                )
            )
            XCTFail("Expected verification failure")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
            XCTAssertFalse(try outputDirectoryContainsTemporaryWAV(outputDirectory))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: outputDirectory
                        .appendingPathComponent("Short Source - 44100Hz 24bit.wav")
                        .path
                )
            )
        }
    }

    func testMonoConversionMixesBothStereoChannels() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        let preset = AudioPreset(
            sampleRate: 48000,
            bitDepth: 24,
            channelCount: 1,
            channelMode: .mono
        )
        let converter = NativeAudioConverter()

        for (name, activeChannel) in [("Left Only", 0), ("Right Only", 1)] {
            let sourceURL = directory.appendingPathComponent("\(name).wav")
            try writeSingleChannelStereoWAV(to: sourceURL, activeChannel: activeChannel)

            let result = try await converter.convert(
                ConversionRequest(
                    sourceURL: sourceURL,
                    outputDirectory: outputDirectory,
                    preset: preset,
                    sourceType: .wav
                )
            )

            XCTAssertEqual(result.spec.channelCount, 1)
            XCTAssertGreaterThan(
                try peakAmplitude(of: result.outputURL),
                0.1,
                "\(name) source must contribute to the mono mix"
            )
        }
    }

    private func writeSingleChannelStereoWAV(to url: URL, activeChannel: Int) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frameCount: AVAudioFrameCount = 4_800
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frameCount) {
            let sample = Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(frame) / 48000.0))
            channels[0][frame] = activeChannel == 0 ? sample : 0
            channels[1][frame] = activeChannel == 1 ? sample : 0
        }
        try file.write(from: buffer)
    }

    private func peakAmplitude(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        )
        try file.read(into: buffer)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(channels[channel][frame]))
            }
        }
        return peak
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
        let frameCount: AVAudioFrameCount = 2_048
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            XCTFail("Could not create source audio buffer")
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
                    channels[channel][frame] = Float(frame % 64) / 64.0
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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
