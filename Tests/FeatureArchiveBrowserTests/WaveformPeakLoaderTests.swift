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
}
