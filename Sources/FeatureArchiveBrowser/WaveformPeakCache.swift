import Foundation

/// Shared in-memory peak cache. Loads the hero-resolution envelope once per file, then
/// downsamples for compact row strips so song select never re-decodes the same WAV.
@MainActor
final class WaveformPeakCache {
    static let shared = WaveformPeakCache()
    static let maxEntries = 48

    /// Canonical resolution stored in cache (hero). Row strips downsample from this.
    static let canonicalBarCount = WaveformPeakLoader.defaultBarCount

    private struct Entry {
        let modifiedAt: Date
        let peaks: [Float]
        var lastAccess: Date
    }

    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<[Float], Never>] = [:]

    func peaks(for url: URL, barCount: Int) async -> [Float] {
        let standard = url.standardizedFileURL
        let modifiedAt = (try? standard.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        let key = standard.path

        if var cached = cache[key], cached.modifiedAt == modifiedAt {
            cached.lastAccess = Date()
            cache[key] = cached
            return WaveformPeakLoader.downsamplePeaks(cached.peaks, to: barCount)
        }

        if let existing = inFlight[key] {
            let loaded = await existing.value
            return WaveformPeakLoader.downsamplePeaks(loaded, to: barCount)
        }

        let task = Task<[Float], Never> {
            await WaveformPeakLoader.loadPeaks(from: standard, barCount: Self.canonicalBarCount)
        }
        inFlight[key] = task
        let loaded = await task.value
        inFlight[key] = nil

        cache[key] = Entry(modifiedAt: modifiedAt, peaks: loaded, lastAccess: Date())
        evictIfNeeded()
        return WaveformPeakLoader.downsamplePeaks(loaded, to: barCount)
    }

    func clear() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        cache.removeAll()
    }

    private func evictIfNeeded() {
        guard cache.count > Self.maxEntries else { return }
        let sortedKeys = cache.sorted { $0.value.lastAccess < $1.value.lastAccess }.map(\.key)
        let overflow = cache.count - Self.maxEntries
        for key in sortedKeys.prefix(overflow) {
            inFlight[key]?.cancel()
            inFlight[key] = nil
            cache.removeValue(forKey: key)
        }
    }
}
