import AVFoundation
import XCTest
@testable import NikoMusicCore

final class MixdownKeyEstimatorTests: XCTestCase {
    func testEstimatesKeyForHighSampleRateMixdown() throws {
        // At 96 kHz the 70 Hz autocorrelation lag (1371 frames) exceeds the 1024-frame
        // analysis window; the estimator used to return nil for every such file.
        for sampleRate in [48_000.0, 96_000.0] {
            let url = try writeSineWAV(frequency: 440, sampleRate: sampleRate, seconds: 4)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertNotNil(MixdownKeyEstimator.estimate(url: url), "no key at \(Int(sampleRate)) Hz")
        }
    }

    func testKeyLabelMatchesTonicOfPureTone() throws {
        // The key profile was rotated the wrong way, so a pure A came out as "D# major"
        // and a pure D as "A# major".
        for (frequency, expected) in [(440.0, "A major"), (293.66, "D major"), (392.0, "G major")] {
            let url = try writeSineWAV(frequency: frequency, sampleRate: 48_000, seconds: 4)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertEqual(MixdownKeyEstimator.estimate(url: url)?.key, expected, "\(frequency) Hz")
        }
    }

    private func writeSineWAV(frequency: Double, sampleRate: Double, seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("key-estimator-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(0.5 * sin(2 * Double.pi * frequency * Double(frame) / sampleRate))
        }
        try file.write(from: buffer)
        return url
    }
}
