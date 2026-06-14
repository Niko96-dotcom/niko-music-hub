import Foundation

public struct HelperToolSettings: Equatable, Codable, Sendable {
    public var ffmpeg: URL?
    public var ffprobe: URL?
    public var ytDlp: URL?
    public var demucsMlx: URL?

    public init(
        ffmpeg: URL? = nil,
        ffprobe: URL? = nil,
        ytDlp: URL? = nil,
        demucsMlx: URL? = nil
    ) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.ytDlp = ytDlp
        self.demucsMlx = demucsMlx
    }
}
