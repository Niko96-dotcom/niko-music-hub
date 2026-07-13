import AVFoundation
import Foundation

public struct MixdownKeyEstimate: Equatable, Sendable {
    public let key: String
    public let confidence: String

    public init(key: String, confidence: String) {
        self.key = key
        self.confidence = confidence
    }
}

/// Display-only musical key estimate from a mixdown file.
public enum MixdownKeyEstimator {
    private static let pitchClasses = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    public static func estimate(url: URL) -> MixdownKeyEstimate? {
        guard !Task.isCancelled else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        let windowFrames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(sampleRate * 4)))
        guard windowFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: windowFrames) else {
            return nil
        }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 512 else { return nil }

        var histogram = Array(repeating: 0.0, count: 12)
        let hop = max(512, frameCount / 200)
        var index = 0
        while index + 1024 < frameCount {
            guard !Task.isCancelled else { return nil }
            let pitch = estimatePitchClass(
                samples: channelData,
                start: index,
                count: 1024,
                sampleRate: sampleRate
            )
            if let pitch {
                histogram[pitch] += 1
            }
            index += hop
        }
        guard histogram.reduce(0, +) >= 8 else { return nil }

        guard let best = bestKeyMatch(histogram: histogram) else { return nil }
        return MixdownKeyEstimate(key: best, confidence: "estimated")
    }

    private static func estimatePitchClass(
        samples: UnsafePointer<Float>,
        start: Int,
        count: Int,
        sampleRate: Double
    ) -> Int? {
        var bestLag = 0
        var bestCorrelation = 0.0
        let minLag = Int(sampleRate / 400)
        let maxLag = Int(sampleRate / 70)
        guard maxLag < count else { return nil }
        for lag in minLag...maxLag {
            guard !Task.isCancelled else { return nil }
            var sum = 0.0
            var index = 0
            while index + lag < count {
                if index.isMultiple(of: 128), Task.isCancelled { return nil }
                sum += Double(samples[start + index] * samples[start + index + lag])
                index += 1
            }
            if sum > bestCorrelation {
                bestCorrelation = sum
                bestLag = lag
            }
        }
        guard bestLag > 0, bestCorrelation > 0 else { return nil }
        let frequency = sampleRate / Double(bestLag)
        guard (65...900).contains(frequency) else { return nil }
        let midi = 69 + 12 * log2(frequency / 440)
        let pitchClass = (Int(midi.rounded()) % 12 + 12) % 12
        return pitchClass
    }

    private static func bestKeyMatch(histogram: [Double]) -> String? {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return nil }
        let normalized = histogram.map { $0 / total }
        var bestScore = -Double.infinity
        var bestLabel: String?
        for root in 0..<12 {
            let majorScore = correlation(normalized, profile: majorProfile, root: root)
            let minorScore = correlation(normalized, profile: minorProfile, root: root)
            if majorScore > bestScore {
                bestScore = majorScore
                bestLabel = "\(pitchClasses[root]) major"
            }
            if minorScore > bestScore {
                bestScore = minorScore
                bestLabel = "\(pitchClasses[root]) minor"
            }
        }
        return bestLabel
    }

    private static func correlation(_ histogram: [Double], profile: [Double], root: Int) -> Double {
        var sum = 0.0
        for index in 0..<12 {
            let rotated = profile[(index + root) % 12]
            sum += histogram[index] * rotated
        }
        return sum
    }
}
