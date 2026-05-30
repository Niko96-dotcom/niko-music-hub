import AVFoundation
import Foundation

/// Finds a sensible playback start near the loudest section (hook) of a preview file.
public enum PreviewHookLocator: Sendable {
    public static let analysisWindowSeconds: Double = 4
    public static let sampleIntervalSeconds: Double = 0.25
    public static let hookLeadInSeconds: Double = 2

    public static func hookStartSeconds(for url: URL) async -> TimeInterval? {
        await Task.detached(priority: .utility) {
            hookStartSecondsSync(for: url)
        }.value
    }

    static func hookStartSecondsSync(for url: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = audioFile.length
        guard totalFrames > 0, sampleRate > 0 else { return nil }

        let windowFrames = AVAudioFrameCount(sampleRate * analysisWindowSeconds)
        let hopFrames = AVAudioFrameCount(sampleRate * sampleIntervalSeconds)
        guard windowFrames > 0, hopFrames > 0, totalFrames > windowFrames else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else {
            return nil
        }

        var bestEnergy = -Double.infinity
        var bestStartFrame: AVAudioFramePosition = 0
        var position: AVAudioFramePosition = 0

        while position + AVAudioFramePosition(windowFrames) <= totalFrames {
            audioFile.framePosition = position
            do {
                try audioFile.read(into: buffer, frameCount: windowFrames)
            } catch {
                break
            }
            let energy = rmsEnergy(buffer: buffer)
            if energy > bestEnergy {
                bestEnergy = energy
                bestStartFrame = position
            }
            position += AVAudioFramePosition(hopFrames)
        }

        guard bestEnergy.isFinite else { return nil }
        let hookStart = Double(bestStartFrame) / sampleRate
        return max(0, hookStart - hookLeadInSeconds)
    }

    private static func rmsEnergy(buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frameLength > 0, channels > 0 else { return 0 }

        if let floatChannels = buffer.floatChannelData {
            var sum: Double = 0
            var count = 0
            for channel in 0..<channels {
                for frame in 0..<frameLength {
                    let sample = Double(floatChannels[channel][frame])
                    sum += sample * sample
                    count += 1
                }
            }
            return count > 0 ? sum / Double(count) : 0
        }

        if let int16Channels = buffer.int16ChannelData {
            var sum: Double = 0
            var count = 0
            for channel in 0..<channels {
                for frame in 0..<frameLength {
                    let normalized = Double(int16Channels[channel][frame]) / Double(Int16.max)
                    sum += normalized * normalized
                    count += 1
                }
            }
            return count > 0 ? sum / Double(count) : 0
        }

        return 0
    }
}
