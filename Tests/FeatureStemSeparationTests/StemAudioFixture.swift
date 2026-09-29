import AVFAudio
import Foundation

/// A few frames of real PCM WAV. The stem scanner accepts only files that decode,
/// so fixtures standing in for backend output must be actual audio.
enum StemAudioFixture {
    static let wavData: Data = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stem-fixture-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: settings)
            guard let format = file?.processingFormat,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)
            else { fatalError("Could not build the stem audio fixture") }
            buffer.frameLength = 64
            try file?.write(from: buffer)
            file = nil // AVAudioFile finalizes the WAV header when released.
            return try Data(contentsOf: url)
        } catch {
            fatalError("Could not build the stem audio fixture: \(error)")
        }
    }()
}
