import AVFoundation
import Foundation

/// Builds a compact peak envelope for waveform UI without materializing every PCM sample.
///
/// Real mixdowns are often multi-minute stereo WAVs. The previous implementation appended
/// every normalized sample into a giant `[Float]` then downsampled — that dominated song-select
/// latency. This path seeks to sparse windows across the file and only decodes those slices.
enum WaveformPeakLoader {
    /// Default hero resolution.
    static let defaultBarCount = 120
    /// Cap how much of the timeline we cover for visualization.
    static let maxAnalysisSeconds: Double = 240
    /// Frames decoded per bar window (small = fast).
    static let windowFrames: AVAudioFrameCount = 2_048

    static func loadPeaks(from url: URL, barCount: Int = defaultBarCount) async -> [Float] {
        let targetBars = max(barCount, 8)
        return await Task.detached(priority: .userInitiated) {
            if let peaks = loadPeaksWithAudioFile(from: url, barCount: targetBars) {
                return peaks
            }
            return await loadPeaksWithAssetReader(from: url, barCount: targetBars)
        }.value
    }

    private static func loadPeaksWithAudioFile(from url: URL, barCount: Int) -> [Float]? {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return nil
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = audioFile.length
        guard totalFrames > 0, sampleRate > 0 else { return [] }

        let maxFrames = AVAudioFramePosition(sampleRate * maxAnalysisSeconds)
        let framesToCover = min(totalFrames, maxFrames)
        guard framesToCover > 0 else { return [] }

        let window = AVAudioFrameCount(min(AVAudioFramePosition(windowFrames), framesToCover))
        guard window > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window) else {
            return []
        }

        var buckets = Array(repeating: Float(0), count: barCount)
        let channelCount = Int(format.channelCount)

        for bar in 0..<barCount {
            let start = AVAudioFramePosition(
                (Double(bar) / Double(barCount)) * Double(framesToCover)
            )
            let remaining = framesToCover - start
            guard remaining > 0 else { break }
            let framesThisPass = AVAudioFrameCount(min(AVAudioFramePosition(window), remaining))
            audioFile.framePosition = start
            do {
                try audioFile.read(into: buffer, frameCount: framesThisPass)
            } catch {
                continue
            }
            buckets[bar] = peakAmplitude(buffer: buffer, channelCount: channelCount)
        }

        guard buckets.contains(where: { $0 > 0 }) else { return [] }
        return buckets
    }

    /// Downsample a denser peak array for compact row strips without re-reading audio.
    static func downsamplePeaks(_ peaks: [Float], to barCount: Int) -> [Float] {
        let target = max(barCount, 8)
        guard !peaks.isEmpty else { return [] }
        if peaks.count == target { return peaks }
        if peaks.count < target {
            var padded = peaks
            padded.append(contentsOf: Array(repeating: peaks.last ?? 0, count: target - peaks.count))
            return padded
        }
        let chunkSize = max(1, peaks.count / target)
        return (0..<target).map { index in
            let start = index * chunkSize
            let end = min(start + chunkSize, peaks.count)
            guard start < end else { return 0 }
            return peaks[start..<end].max() ?? 0
        }
    }

    private static func peakAmplitude(buffer: AVAudioPCMBuffer, channelCount: Int) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        // Subsample inside the window — envelope ranking does not need every sample.
        let frameStride = max(1, frameLength / 256)
        var peak: Float = 0

        if let channels = buffer.floatChannelData {
            for channel in 0..<channelCount {
                var frame = 0
                while frame < frameLength {
                    peak = max(peak, abs(channels[channel][frame]))
                    frame += frameStride
                }
            }
            return min(peak, 1)
        }

        if let channels = buffer.int16ChannelData {
            for channel in 0..<channelCount {
                var frame = 0
                while frame < frameLength {
                    peak = max(peak, Float(abs(Int(channels[channel][frame]))) / Float(Int16.max))
                    frame += frameStride
                }
            }
            return min(peak, 1)
        }

        return 0
    }

    /// Fallback for formats `AVAudioFile` rejects — still streams into buckets (no giant array).
    private static func loadPeaksWithAssetReader(from url: URL, barCount: Int) async -> [Float] {
        let asset = AVURLAsset(url: url)
        let track: AVAssetTrack
        do {
            guard let loadedTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                return []
            }
            track = loadedTrack
        } catch {
            return []
        }
        let duration = try? await asset.load(.duration)
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return []
        }

        if let duration {
            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds.isFinite, durationSeconds > 0 {
                let analysisDuration = min(durationSeconds, maxAnalysisSeconds)
                reader.timeRange = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: analysisDuration, preferredTimescale: 600)
                )
            }
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return [] }

        var buckets = Array(repeating: Float(0), count: barCount)
        var sampleIndex = 0
        let estimatedSamples = max(barCount * 2_000, 50_000)
        let stride = max(1, estimatedSamples / (barCount * 64))

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let block = CMSampleBufferGetDataBuffer(buffer) else { break }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            guard let dataPointer, length > 0 else { break }
            let sampleCount = length / MemoryLayout<Int16>.size
            dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { pointer in
                var index = 0
                while index < sampleCount {
                    let normalized = min(Float(abs(Int(pointer[index]))) / Float(Int16.max), 1)
                    let bucket = min(barCount - 1, (sampleIndex * barCount) / estimatedSamples)
                    if normalized > buckets[bucket] {
                        buckets[bucket] = normalized
                    }
                    sampleIndex += 1
                    index += stride
                }
            }
            if sampleIndex >= estimatedSamples { break }
        }

        guard buckets.contains(where: { $0 > 0 }) else { return [] }
        return buckets
    }
}
