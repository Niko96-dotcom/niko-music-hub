import AVFoundation
import Foundation

enum WaveformPeakLoader {
    static func loadPeaks(from url: URL, barCount: Int = 120) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return []
        }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        guard reader.startReading() else { return [] }

        var samples: [Float] = []
        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let block = CMSampleBufferGetDataBuffer(buffer) else { break }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            guard let dataPointer else { break }
            let sampleCount = length / MemoryLayout<Int16>.size
            dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { pointer in
                for index in 0..<sampleCount {
                    let normalized = Float(abs(pointer[index])) / Float(Int16.max)
                    samples.append(normalized)
                }
            }
        }
        guard !samples.isEmpty else { return [] }
        return downsample(samples, barCount: max(barCount, 8))
    }

    private static func downsample(_ samples: [Float], barCount: Int) -> [Float] {
        let chunkSize = max(1, samples.count / barCount)
        return (0..<barCount).map { index in
            let start = index * chunkSize
            let end = min(start + chunkSize, samples.count)
            guard start < end else { return 0 }
            return samples[start..<end].max() ?? 0
        }
    }
}
