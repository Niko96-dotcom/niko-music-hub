import Foundation

public struct HelperToolSettings: Equatable, Codable, Sendable {
    public var ffmpeg: URL?
    public var ffprobe: URL?
    public var ytDlp: URL?

    public init(
        ffmpeg: URL? = nil,
        ffprobe: URL? = nil,
        ytDlp: URL? = nil
    ) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.ytDlp = ytDlp
    }
}
