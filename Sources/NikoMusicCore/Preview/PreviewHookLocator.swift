import AVFoundation
import Foundation

/// Finds a sensible playback start near the loudest section (hook) of a preview file.
///
/// Tuned for interactive song-select: sparse hops over a capped analysis window so we never
/// fully decode multi-minute mixdowns on every prepare.
public enum PreviewHookLocator: Sendable {
    /// Sliding energy window.
    public static let analysisWindowSeconds: Double = 2
    /// Hop between windows — sparse enough for interactive UI.
    public static let sampleIntervalSeconds: Double = 1.0
    /// Start playback slightly before the loudest window.
    public static let hookLeadInSeconds: Double = 1.5
    /// Only scan the first N seconds (hooks live early in most mixdowns).
    public static let maxAnalysisSeconds: Double = 90

    public static func hookStartSeconds(for url: URL) async -> TimeInterval? {
        await Task.detached(priority: .utility) {
            hookStartSecondsSync(for: url)
        }.value
    }

    public static func hookStartSecondsSync(for url: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = audioFile.length
        guard totalFrames > 0, sampleRate > 0 else { return nil }

        let windowFrames = AVAudioFrameCount(sampleRate * analysisWindowSeconds)
        let hopFrames = AVAudioFrameCount(sampleRate * sampleIntervalSeconds)
        let maxFrames = AVAudioFramePosition(sampleRate * maxAnalysisSeconds)
        let framesToScan = min(totalFrames, maxFrames)
        guard windowFrames > 0, hopFrames > 0, framesToScan > AVAudioFramePosition(windowFrames) else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else {
            return nil
        }

        var bestEnergy = -Double.infinity
        var bestStartFrame: AVAudioFramePosition = 0
        var position: AVAudioFramePosition = 0

        while position + AVAudioFramePosition(windowFrames) <= framesToScan {
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

        guard bestEnergy.isFinite, bestEnergy > 0 else { return nil }
        let hookStart = Double(bestStartFrame) / sampleRate
        return max(0, hookStart - hookLeadInSeconds)
    }

    private static func rmsEnergy(buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frameLength > 0, channels > 0 else { return 0 }

        // Subsample frames inside the window — energy ranking does not need every sample.
        let frameStride = max(1, frameLength / 512)

        if let floatChannels = buffer.floatChannelData {
            var sum: Double = 0
            var count = 0
            for channel in 0..<channels {
                var frame = 0
                while frame < frameLength {
                    let sample = Double(floatChannels[channel][frame])
                    sum += sample * sample
                    count += 1
                    frame += frameStride
                }
            }
            return count > 0 ? sum / Double(count) : 0
        }

        if let int16Channels = buffer.int16ChannelData {
            var sum: Double = 0
            var count = 0
            for channel in 0..<channels {
                var frame = 0
                while frame < frameLength {
                    let normalized = Double(int16Channels[channel][frame]) / Double(Int16.max)
                    sum += normalized * normalized
                    count += 1
                    frame += frameStride
                }
            }
            return count > 0 ? sum / Double(count) : 0
        }

        return 0
    }
}
