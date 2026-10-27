import Foundation

// The helper builds this release installs: FFmpeg and ffprobe 9.0.2 (macOS arm64 release build by Martin Riedl,
// Developer ID team KU3N25YGLU) and uv 0.13.6. Each SHA-256 was checked against the host's own checksum file
// when the pin was made.
extension HelperToolPins {
    public static let release = HelperToolPins(
        ffmpeg: PinnedDownload(
            url: URL(string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip")!,
            sha256: "c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"
        ),
        ffprobe: PinnedDownload(
            url: URL(string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffprobe.zip")!,
            sha256: "fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6"
        ),
        uv: PinnedDownload(
            url: URL(string: "https://github.com/astral-sh/uv/releases/download/0.13.6/uv-aarch64-apple-darwin.tar.gz")!,
            sha256: "60fbd5c8a1ed681845eea28d9d622fcde03c51e91a43465b64a1e17db1ed3472"
        )
    )
}
