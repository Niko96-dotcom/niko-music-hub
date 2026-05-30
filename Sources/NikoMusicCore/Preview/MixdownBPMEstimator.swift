import AVFoundation
import Foundation

public struct MixdownBPMEstimate: Equatable, Sendable {
    public let bpm: Double
    public let confidence: String

    public init(bpm: Double, confidence: String) {
        self.bpm = bpm
        self.confidence = confidence
    }
}

/// Best-effort BPM read from a mixdown file (display only; no network).
public enum MixdownBPMEstimator {
    public static func estimate(url: URL) -> MixdownBPMEstimate? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = Double(file.length) / sampleRate
        guard duration >= 4 else { return nil }

        let maxFrames = AVAudioFrameCount(sampleRate * 2)
        let windowFrames = AVAudioFrameCount(
            min(file.length, AVAudioFramePosition(maxFrames))
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: windowFrames) else {
            return nil
        }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let hop = max(256, frameCount / 200)
        var peaks: [Int] = []
        var lastPeak = -Int.max
        let threshold = peakThreshold(samples: channelData, count: frameCount)
        var index = 0
        while index < frameCount {
            let sample = abs(channelData[index])
            if sample >= threshold && index - lastPeak > hop {
                peaks.append(index)
                lastPeak = index
            }
            index += hop / 4
        }
        guard peaks.count >= 3 else { return nil }

        let intervals = zip(peaks.dropFirst(), peaks).map { Double($0.0 - $0.1) / sampleRate }
        let medianInterval = intervals.sorted()[intervals.count / 2]
        guard medianInterval > 0.2, medianInterval < 2.0 else { return nil }
        let bpm = 60.0 / medianInterval
        guard (40...220).contains(bpm) else { return nil }
        return MixdownBPMEstimate(bpm: (bpm * 10).rounded() / 10, confidence: "estimated")
    }

    private static func peakThreshold(samples: UnsafePointer<Float>, count: Int) -> Float {
        var sum: Float = 0
        var index = 0
        let step = max(1, count / 500)
        var samplesRead = 0
        while index < count {
            sum += abs(samples[index])
            samplesRead += 1
            index += step
        }
        let average = samplesRead > 0 ? sum / Float(samplesRead) : 0
        return max(0.02, average * 2.5)
    }
}
