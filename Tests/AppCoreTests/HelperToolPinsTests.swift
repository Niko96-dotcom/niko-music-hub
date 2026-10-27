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

    /// `uv pip install --require-hashes` needs every package at one version with its hashes; PyTorch stays out.
    func testReleaseDemucsLockPinsEveryPackageWithItsHashes() {
        let entries = HelperToolPins.release.demucsRequirements
            .replacingOccurrences(of: "\\\n", with: " ")
            .split(separator: "\n")
            .map { $0.split(whereSeparator: \.isWhitespace) }
            .filter { !$0.isEmpty }
        XCTAssertGreaterThan(entries.count, 3)
        for entry in entries {
            let requirement = String(entry[0])
            XCTAssertTrue(requirement.contains("=="), "not pinned to one version: \(requirement)")
            let hashes = entry.dropFirst().filter { $0.hasPrefix("--hash=sha256:") }
            XCTAssertFalse(hashes.isEmpty, "no hash for \(requirement)")
            XCTAssertEqual(hashes.count, entry.count - 1, "unexpected option for \(requirement)")
        }
        let names = entries.map { String($0[0].split(separator: "=")[0]) }
        XCTAssertTrue(names.contains("demucs-mlx"))
        XCTAssertFalse(names.contains { $0 == "torch" || $0 == "demucs" || $0.contains("[") }, "\(names)")
    }
}
