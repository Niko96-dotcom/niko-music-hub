import XCTest
@testable import FeatureArchiveBrowser

final class WaveformPeakLoaderTests: XCTestCase {
    func testLoadsPeaksFromFixtureMixdown() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-fixture-\(UUID().uuidString).wav")
        let samples = Array(repeating: Int16(4_000), count: 44_100) + Array(repeating: Int16(-4_000), count: 44_100)
        try makeMono16BitWAV(samples: samples, at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let peaks = await WaveformPeakLoader.loadPeaks(from: url, barCount: 32)
        XCTAssertFalse(peaks.isEmpty)
        XCTAssertEqual(peaks.count, 32)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testLoadsPeaksWhenPCMContainsFullNegativeSample() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-int16-min-\(UUID().uuidString).wav")
        let samples = [0] + Array(repeating: Int16.min, count: 4_096) + [Int16.max]
        try makeMono16BitWAV(samples: samples, at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let peaks = await WaveformPeakLoader.loadPeaks(from: url, barCount: 8)

        XCTAssertFalse(peaks.isEmpty)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertGreaterThanOrEqual(peaks.max() ?? 0, 0.99)
    }

    func testDownsamplePeaksReducesBarCountWithoutRereading() {
        let dense = (0..<120).map { Float($0 % 10) / 10 }
        let compact = WaveformPeakLoader.downsamplePeaks(dense, to: 48)
        XCTAssertEqual(compact.count, 48)
        XCTAssertTrue(compact.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testSparsePeakLoadCompletesQuicklyOnLongSyntheticWav() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("peaks-long-\(UUID().uuidString).wav")
        try makeMono16BitWAV(samples: Array(repeating: Int16(1_000), count: 44_100 * 45), at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let started = Date()
        let peaks = await WaveformPeakLoader.loadPeaks(from: url, barCount: 64)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(peaks.count, 64)
        XCTAssertFalse(peaks.isEmpty)
        XCTAssertLessThan(elapsed, 2.5, "Peak load took \(elapsed)s — expected sparse window sampling")
    }

    @MainActor
    func testSharedCacheEvictsBeyondMaxEntries() async throws {
        await MainActor.run { WaveformPeakCache.shared.clear() }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-cache-evict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<(WaveformPeakCache.maxEntries + 3) {
            let url = directory.appendingPathComponent("clip-\(index).wav")
            try makeMono16BitWAV(samples: Array(repeating: Int16(1_000), count: 512), at: url)
            _ = await WaveformPeakCache.shared.peaks(for: url, barCount: 16)
        }

        let mirror = Mirror(reflecting: WaveformPeakCache.shared)
        let cacheField = mirror.children.first { $0.label == "cache" }?.value as? [String: Any]
        XCTAssertLessThanOrEqual(cacheField?.count ?? Int.max, WaveformPeakCache.maxEntries)
    }

    func testSharedCacheServesRowStripFromCanonicalHeroLoad() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-cache-\(UUID().uuidString).wav")
        let samples = (0..<88_200).map { index in Int16(index % 2 == 0 ? 6_000 : -6_000) }
        try makeMono16BitWAV(samples: samples, at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await MainActor.run { WaveformPeakCache.shared.clear() }

        let hero = await WaveformPeakCache.shared.peaks(for: url, barCount: WaveformPeakLoader.defaultBarCount)
        let row = await WaveformPeakCache.shared.peaks(for: url, barCount: 48)

        XCTAssertEqual(hero.count, WaveformPeakLoader.defaultBarCount)
        XCTAssertEqual(row.count, 48)
        XCTAssertFalse(hero.isEmpty)
        XCTAssertFalse(row.isEmpty)
    }

    private func makeMono16BitWAV(samples: [Int16], at url: URL) throws {
        var data = Data()
        let sampleRate: UInt32 = 44_100
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channelCount * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)
        let audioByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        let riffByteCount = UInt32(36) + audioByteCount

        appendASCII("RIFF", to: &data)
        appendLittleEndian(riffByteCount, to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channelCount, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        appendASCII("data", to: &data)
        appendLittleEndian(audioByteCount, to: &data)
        for sample in samples {
            appendLittleEndian(UInt16(bitPattern: sample), to: &data)
        }

        try data.write(to: url, options: .atomic)
    }

    private func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
