import AVFoundation
import Foundation

/// Reads metadata only; never decodes samples during an archive scan.
enum PreviewWAVDurationReader {
    /// `canonicalPath` is the file's resolved path, as `canonicalPath(of:)` returns it.
    static func shouldReadDuration(canonicalPath: String) -> Bool {
        !canonicalPath.contains("/Library/CloudStorage/")
    }

    static func canonicalPath(of fileURL: URL) -> String {
        PathResolutionProbe.resolvingSymlinks(fileURL).standardizedFileURL.path
    }

    static func durationSeconds(for fileURL: URL) -> Double? {
        if fileURL.pathExtension.lowercased() == "wav" {
            return wavDuration(for: fileURL)
        }
        guard let file = try? AVAudioFile(forReading: fileURL),
              file.length > 0, file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private static func wavDuration(for fileURL: URL) -> Double? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count == 12,
              String(data: header[0..<4], encoding: .ascii) == "RIFF",
              String(data: header[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        let riffEnd = UInt64(uint32(header, at: 4)) + 8
        var offset: UInt64 = 12
        var bytesPerSecond: UInt32?
        var dataSize: UInt32?
        // DAW WAVs can contain JUNK, bext, LIST and extended fmt chunks. Seek
        // past their payloads, including RIFF's odd-byte padding, with a bound
        // on work for malformed files. Never assume audio starts at byte 44.
        for _ in 0..<256 {
            guard offset + 8 <= riffEnd,
                  (try? handle.seek(toOffset: offset)) != nil,
                  let chunk = try? handle.read(upToCount: 8), chunk.count == 8 else { return nil }
            let size = uint32(chunk, at: 4)
            guard offset + 8 + UInt64(size) <= riffEnd else { return nil }
            let tag = String(data: chunk[0..<4], encoding: .ascii)
            if tag == "fmt " {
                guard size >= 16, let format = try? handle.read(upToCount: 16), format.count == 16 else { return nil }
                let encoding = UInt16(format[0]) | UInt16(format[1]) << 8
                guard [1, 3, 0xfffe].contains(encoding) else { return nil }
                bytesPerSecond = uint32(format, at: 8)
            } else if tag == "data" {
                dataSize = size
            }
            if let rate = bytesPerSecond, rate > 0, let size = dataSize {
                return Double(size) / Double(rate)
            }
            offset += 8 + UInt64(size) + UInt64(size % 2)
        }
        return nil
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}
