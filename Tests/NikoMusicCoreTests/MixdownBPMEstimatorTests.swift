import XCTest
@testable import NikoMusicCore

final class MixdownBPMEstimatorTests: XCTestCase {
    func testEstimateDoesNotTrapOnFixtureWav() throws {
        try CubaseFixtures.ensureGenerated()
        let url = CubaseFixtures.archiveRoot
            .appendingPathComponent("90s Rave/Mixdown/Graffiti master.wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture wav missing")
        }

        _ = MixdownBPMEstimator.estimate(url: url)
    }
}
