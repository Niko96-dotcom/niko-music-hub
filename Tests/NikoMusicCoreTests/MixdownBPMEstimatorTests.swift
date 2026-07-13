import XCTest
@testable import NikoMusicCore

final class MixdownBPMEstimatorTests: XCTestCase {
    func testEstimateDoesNotTrapOnFixtureWav() throws {
        try CubaseFixtures.ensureGenerated()
        let url = CubaseFixtures.archiveRoot
            .appendingPathComponent("90s Rave/Mixdown/Graffiti master.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Required fixture WAV is missing")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        _ = MixdownBPMEstimator.estimate(url: url)
    }
}
