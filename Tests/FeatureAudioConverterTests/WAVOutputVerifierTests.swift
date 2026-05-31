import AVFoundation
import AppCore
import FeatureAudioConverter
import XCTest

final class WAVOutputVerifierTests: XCTestCase {
    func testVerifiesMatchingWAVSpec() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("verified.wav")
        try writeTestWAV(
            to: url,
            sampleRate: 44100,
            bitDepth: 24,
            channelCount: 2
        )

        let spec = try WAVOutputVerifier().verify(
            url: url,
            expectedSpec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2)
        )

        XCTAssertEqual(spec, WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2))
    }

    func testRejectsMissingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingURL = directory.appendingPathComponent("missing.wav")

        XCTAssertThrowsError(
            try WAVOutputVerifier().verify(
                url: missingURL,
                expectedSpec: WAVOutputSpec(sampleRate: 44100, bitDepth: 24, channelCount: 2)
            )
        ) { error in
            XCTAssertEqual(error as? WAVOutputVerificationError, .missingFile(missingURL))
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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideCubaseHubTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
