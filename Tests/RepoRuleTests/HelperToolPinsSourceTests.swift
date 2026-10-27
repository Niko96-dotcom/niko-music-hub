import XCTest

/// A moving link (`latest`) installs whatever the host serves that day, and its checksum came from the same
/// host. FFmpeg, ffprobe and uv install the build in `HelperToolPins.release`, checked against the SHA-256 there;
/// yt-dlp installs the newest tag's files, checked against its signed checksum list.
/// AGENTS.md row "Pinned helpers"; docs/architecture.md § Helper tools.
final class HelperToolPinsSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Pinned helpers",
        why: "A moving link installs whatever the host serves today, checked only against the host's own checksum",
        see: "AGENTS.md row \"Pinned helpers\"; docs/architecture.md § Helper tools",
        fix: "Pin the exact build and its SHA-256 in HelperToolPins.release and download that link"
    )

    /// yt-dlp follows the newest release on purpose (YouTube breaks old builds within weeks), but it asks GitHub's API
    /// for the tag and downloads that release's files by name; its checksum list must carry the yt-dlp signature.
    func testHelperDownloadsUseNoMovingLink() {
        let files = SourceTree.swiftFiles(under: "Sources/AppCore/HelperTools/", atLeast: 5)
        Self.rule.check(SourceTree.matches(Self.pattern, in: files, .codeAndStrings), "downloads through a moving link")
    }

    /// The detector must catch the shipped links, or it guards nothing.
    func testDetectorCatchesTheShippedLinks() {
        let regex = SourceTree.regex(Self.pattern)
        let shipped = [
            #"string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip""#,
            #"string: "https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz""#,
            #"string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos""#,
        ]
        for line in shipped {
            XCTAssertFalse(SourceTree.matches(regex, in: SourceLex.strippedCommentsOnly(line)).isEmpty, "Detector misses: \(line)")
        }
        let pinned = #"url: URL(string: "https://github.com/astral-sh/uv/releases/download/0.13.6/uv-aarch64-apple-darwin.tar.gz")!"#
        XCTAssertEqual(SourceTree.matches(regex, in: SourceLex.strippedCommentsOnly(pinned)), [], "Detector flags a pinned link")
    }

    private static let pattern = #"https://[^"\s]*(?:latest/download|redirect/latest)[^"\s]*"#
}
