import XCTest
@testable import NikoMusicCore

final class PreviewHookLocatorTests: XCTestCase {
    func testFindsHookInFixtureWav() throws {
        try CubaseFixtures.ensureGenerated()
        let url = CubaseFixtures.archiveRoot
            .appendingPathComponent("90s Rave/Mixdown/Graffiti master.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture wav missing")
        }

        let hook = try XCTUnwrap(PreviewHookLocator.hookStartSecondsSync(for: url))
        XCTAssertGreaterThanOrEqual(hook, 0)
        // Sparse locator must stay within the capped analysis window (+ lead-in floor).
        XCTAssertLessThanOrEqual(hook, PreviewHookLocator.maxAnalysisSeconds)
    }

    func testSparseLocatorCompletesQuicklyOnLongSyntheticWav() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-long-\(UUID().uuidString).wav")
        // ~30s of silence + a loud burst near 8s — must not fully decode minutes of audio.
        try makeMono16BitWAV(seconds: 30, loudBurstAt: 8, at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let started = Date()
        let hook = try XCTUnwrap(PreviewHookLocator.hookStartSecondsSync(for: url))
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 2.5, "Hook scan took \(elapsed)s — expected sparse/capped analysis")
        XCTAssertGreaterThan(hook, 4)
        XCTAssertLessThan(hook, 10)
    }

    private func makeMono16BitWAV(seconds: Int, loudBurstAt: Int, at url: URL) throws {
        let sampleRate = 8_000
        let totalSamples = seconds * sampleRate
        var samples = Array(repeating: Int16(0), count: totalSamples)
        let burstStart = loudBurstAt * sampleRate
        let burstEnd = min(totalSamples, burstStart + sampleRate)
        for index in burstStart..<burstEnd {
            samples[index] = index % 2 == 0 ? Int16.max : Int16.min
        }

        var data = Data()
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channelCount * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let audioByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        let riffByteCount = UInt32(36) + audioByteCount

        func appendASCII(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendLE(riffByteCount)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendLE(UInt32(16))
        appendLE(UInt16(1))
        appendLE(channelCount)
        appendLE(UInt32(sampleRate))
        appendLE(byteRate)
        appendLE(blockAlign)
        appendLE(bitsPerSample)
        appendASCII("data")
        appendLE(audioByteCount)
        for sample in samples {
            appendLE(UInt16(bitPattern: sample))
        }
        try data.write(to: url, options: .atomic)
    }
}
