import XCTest
@testable import NikoMusicCore

final class PreviewCandidateDetectorTests: XCTestCase {
    func testDetectsSupportedAudioExtensions() throws {
        try CubaseFixtures.ensureGenerated()
        let detector = PreviewCandidateDetector()
        let neonFolder = CubaseFixtures.archiveRoot.appendingPathComponent("Neon Hook", isDirectory: true)
        let candidates = try detector.detectCandidates(in: neonFolder)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.fileName.hasSuffix(".wav") })
    }
}
