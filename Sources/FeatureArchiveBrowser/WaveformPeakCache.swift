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

    private struct InFlight {
        let token = UUID()
        let modifiedAt: Date
        let task: Task<[Float], Never>
    }

    private var cache: [String: Entry] = [:]
    private var inFlight: [String: InFlight] = [:]

    func peaks(for url: URL, barCount: Int) async -> [Float] {
        let standard = url.standardizedFileURL
        let key = standard.path
        // External archive roots can sit on cloud volumes. Revision lookup is needed for
        // cache correctness, but it must not run on the SwiftUI main actor while a detail
        // view is mounting.
        let modifiedAt = await Task.detached(priority: .utility) {
            (try? standard.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
        }.value
        guard !Task.isCancelled else { return [] }

        if var cached = cache[key], cached.modifiedAt == modifiedAt {
            cached.lastAccess = Date()
            cache[key] = cached
            return WaveformPeakLoader.downsamplePeaks(cached.peaks, to: barCount)
        }

        if let existing = inFlight[key], existing.modifiedAt == modifiedAt {
            let loaded = await waitForPeakLoad(existing.task)
            guard !Task.isCancelled else {
                if inFlight[key]?.token == existing.token {
                    inFlight[key] = nil
                }
                return []
            }
            return WaveformPeakLoader.downsamplePeaks(loaded, to: barCount)
        }

        inFlight[key]?.task.cancel()
        let canonicalBarCount = Self.canonicalBarCount

        let task = Task.detached(priority: .utility) {
            await WaveformPeakLoader.loadPeaks(from: standard, barCount: canonicalBarCount)
        }
        let loading = InFlight(modifiedAt: modifiedAt, task: task)
        inFlight[key] = loading
        let loaded = await waitForPeakLoad(task)
        guard !Task.isCancelled else {
            if inFlight[key]?.token == loading.token {
                inFlight[key] = nil
            }
            return []
        }

        if inFlight[key]?.token == loading.token {
            inFlight[key] = nil
            cache[key] = Entry(modifiedAt: modifiedAt, peaks: loaded, lastAccess: Date())
            evictIfNeeded()
        }

        return WaveformPeakLoader.downsamplePeaks(loaded, to: barCount)
    }

    func clear() {
        for loading in inFlight.values {
            loading.task.cancel()
        }
        inFlight.removeAll()
        cache.removeAll()
    }

    private func waitForPeakLoad(_ task: Task<[Float], Never>) async -> [Float] {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func evictIfNeeded() {
        guard cache.count > Self.maxEntries else { return }
        let sortedKeys = cache.sorted { $0.value.lastAccess < $1.value.lastAccess }.map(\.key)
        let overflow = cache.count - Self.maxEntries
        for key in sortedKeys.prefix(overflow) {
            inFlight[key]?.task.cancel()
            inFlight[key] = nil
            cache.removeValue(forKey: key)
        }
    }
}
