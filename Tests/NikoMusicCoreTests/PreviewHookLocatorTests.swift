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
    }
}
