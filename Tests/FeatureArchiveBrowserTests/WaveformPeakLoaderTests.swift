import XCTest
@testable import FeatureArchiveBrowser

final class WaveformPeakLoaderTests: XCTestCase {
    func testLoadsPeaksFromFixtureMixdown() async throws {
        try CubaseFixtures.ensureGenerated()
        let url = CubaseFixtures.archiveRoot
            .appendingPathComponent("Neon Hook/Mixdown/Neon Hook v3.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let peaks = await WaveformPeakLoader.loadPeaks(from: url, barCount: 32)
        XCTAssertFalse(peaks.isEmpty)
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
