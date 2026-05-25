import Foundation

enum PreviewWAVDurationReader {
    static func durationSeconds(for fileURL: URL) -> Double? {
        guard fileURL.pathExtension.lowercased() == "wav" else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 44), header.count >= 44 else { return nil }
        guard String(data: header[0..<4], encoding: .ascii) == "RIFF",
              String(data: header[8..<12], encoding: .ascii) == "WAVE" else {
            return nil
        }

        let channels = Int(header[22]) | (Int(header[23]) << 8)
        let sampleRate = UInt32(header[24])
            | (UInt32(header[25]) << 8)
            | (UInt32(header[26]) << 16)
            | (UInt32(header[27]) << 24)
        let bitsPerSample = Int(header[34]) | (Int(header[35]) << 8)
        let dataSize = UInt32(header[40])
            | (UInt32(header[41]) << 8)
            | (UInt32(header[42]) << 16)
            | (UInt32(header[43]) << 24)

        guard channels > 0, sampleRate > 0, bitsPerSample > 0 else { return nil }
        let bytesPerSecond = Double(sampleRate) * Double(channels) * Double(bitsPerSample) / 8
        guard bytesPerSecond > 0 else { return nil }
        return Double(dataSize) / bytesPerSecond
    }
}
