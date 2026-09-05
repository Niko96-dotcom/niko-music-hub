import XCTest
@testable import NikoMusicCore

final class PreviewProductionMaturityPatternTests: XCTestCase {
    func testFixedPatternsPreserveBoundariesPhrasesAndHighestTier() {
        let cases: [(String, PreviewProductionMaturity)] = [
            ("Song.wav", .none), ("Song_masterpiece.wav", .none),
            ("Song remix.wav", .none), ("Song sessions.wav", .none),
            ("Song SKETCHYY.wav", .sketch), ("Song WIP.wav", .sketch),
            ("Song session-bounce.wav", .sessionBounce), ("Song seshy_bounce.wav", .sessionBounce),
            ("Song sessinbounce.wav", .sessionBounce), ("Song demmo.wav", .demo),
            ("Song production.wav", .prod), ("Song rough mix.wav", .mix),
            ("Song MIXDOWN.wav", .mix), ("Song mastered.wav", .master),
            ("Song demmo MSTR.wav", .master), ("é-master-最终.wav", .master),
            ("Song sketch demo prod mix master.wav", .master)
        ]
        // Repeated use exercises the shared expressions and all precedence branches.
        for _ in 0..<3 {
            for (name, expected) in cases {
                XCTAssertEqual(PreviewProductionMaturity.detect(from: name), expected, name)
            }
        }
    }
}
