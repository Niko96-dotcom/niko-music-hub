import AppCore
import XCTest

/// The shipped pins name one exact build each: an https link with its version in the path and a full SHA-256.
final class HelperToolPinsTests: XCTestCase {
    func testReleasePinsNameExactBuilds() {
        let pins = HelperToolPins.release
        for (name, pinned) in [("ffmpeg", pins.ffmpeg), ("ffprobe", pins.ffprobe), ("uv", pins.uv)] {
            XCTAssertEqual(pinned.url.scheme, "https", name)
            XCTAssertFalse(pinned.url.path.contains("latest"), "\(name) follows a moving link: \(pinned.url)")
            XCTAssertNotNil(pinned.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression), "\(name): \(pinned.sha256)")
        }
        XCTAssertEqual(
            pins.ffmpeg.url.deletingLastPathComponent(), pins.ffprobe.url.deletingLastPathComponent(),
            "FFmpeg and ffprobe come from one build"
        )
    }
}
