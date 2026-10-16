import AVFoundation
import XCTest
@testable import NikoMusicCore

final class MixdownBPMEstimatorTests: XCTestCase {
    func testEstimateDoesNotTrapOnFixtureWav() throws {
        try CubaseFixtures.ensureGenerated()
        let url = CubaseFixtures.archiveRoot
            .appendingPathComponent("90s Rave/Mixdown/Graffiti master.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Required fixture WAV is missing")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        _ = MixdownBPMEstimator.estimate(url: url)
    }

    func testSlowClickTracksReturnTempo() throws {
        for bpm in [60.0, 45.0] {
            let url = try writeClickTrack(bpm: bpm, firstOnset: 0.5, seconds: 12)
            defer { try? FileManager.default.removeItem(at: url) }
            let estimate = try XCTUnwrap(MixdownBPMEstimator.estimate(url: url), "No BPM for \(bpm)")
            XCTAssertEqual(estimate.bpm, bpm, accuracy: 0.5)
        }
    }

    private func writeClickTrack(bpm: Double, firstOnset: Double, seconds: Double) throws -> URL {
        let sampleRate = 44_100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) { samples[index] = 0 }
        let clickLength = Int(sampleRate * 0.005)
        var beat = firstOnset
        while beat < seconds {
            let start = Int(beat * sampleRate)
            for index in start..<min(start + clickLength, Int(frames)) { samples[index] = 0.8 }
            beat += 60.0 / bpm
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("click-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
