import Foundation

@MainActor
final class WaveformPeakCache {
    static let shared = WaveformPeakCache()

    private struct Entry {
        let modifiedAt: Date
        let peaks: [Float]
    }

    private var cache: [String: Entry] = [:]

    func peaks(for url: URL, barCount: Int) async -> [Float] {
        let standard = url.standardizedFileURL
        let key = "\(standard.path)|\(barCount)"
        let modifiedAt = (try? standard.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        if let cached = cache[key], cached.modifiedAt == modifiedAt {
            return cached.peaks
        }
        let loaded = await WaveformPeakLoader.loadPeaks(from: standard, barCount: barCount)
        cache[key] = Entry(modifiedAt: modifiedAt, peaks: loaded)
        return loaded
    }

    func clear() {
        cache.removeAll()
    }
}
