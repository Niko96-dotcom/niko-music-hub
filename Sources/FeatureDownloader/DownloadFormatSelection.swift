import Foundation

public enum DownloadMediaKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case audioOnly
    case videoWithAudio

    public var id: String { rawValue }
}

public enum DownloadAudioContainer: String, CaseIterable, Codable, Sendable, Identifiable {
    case best
    case mp3
    case m4a

    public var id: String { rawValue }
}

public enum DownloadVideoQuality: String, CaseIterable, Codable, Sendable, Identifiable {
    case mp4_360
    case mp4_720
    case best

    public var id: String { rawValue }
}

public struct DownloadFormatSelection: Equatable, Sendable, Codable {
    public var mediaKind: DownloadMediaKind
    public var audioContainer: DownloadAudioContainer
    public var videoQuality: DownloadVideoQuality

    public init(
        mediaKind: DownloadMediaKind = .videoWithAudio,
        audioContainer: DownloadAudioContainer = .mp3,
        videoQuality: DownloadVideoQuality = .mp4_360
    ) {
        self.mediaKind = mediaKind
        self.audioContainer = audioContainer
        self.videoQuality = videoQuality
    }

    public static let `default` = DownloadFormatSelection()

    public var summaryLabel: String {
        switch mediaKind {
        case .audioOnly:
            switch audioContainer {
            case .best: return "Audio — best available"
            case .mp3: return "Audio — MP3"
            case .m4a: return "Audio — M4A"
            }
        case .videoWithAudio:
            switch videoQuality {
            case .mp4_360: return "Video + audio — MP4 (360p)"
            case .mp4_720: return "Video + audio — MP4 (720p)"
            case .best: return "Video + audio — best quality"
            }
        }
    }
}

/// yt-dlp `-f` selector and follow-up flags for a download format choice.
public struct YtDlpFormatArguments: Equatable, Sendable {
    public let formatSelector: String
    public let extraArguments: [String]

    public init(formatSelector: String, extraArguments: [String] = []) {
        self.formatSelector = formatSelector
        self.extraArguments = extraArguments
    }
}

public enum YtDlpFormatArgumentBuilder {
    public static func arguments(for selection: DownloadFormatSelection) -> YtDlpFormatArguments {
        switch selection.mediaKind {
        case .audioOnly:
            return audioArguments(container: selection.audioContainer)
        case .videoWithAudio:
            return videoArguments(quality: selection.videoQuality)
        }
    }

    private static func audioArguments(container: DownloadAudioContainer) -> YtDlpFormatArguments {
        switch container {
        case .best:
            return YtDlpFormatArguments(formatSelector: "bestaudio/best")
        case .mp3:
            return YtDlpFormatArguments(
                formatSelector: "bestaudio/best",
                extraArguments: ["--extract-audio", "--audio-format", "mp3"]
            )
        case .m4a:
            return YtDlpFormatArguments(
                formatSelector: "bestaudio/best",
                extraArguments: ["--extract-audio", "--audio-format", "m4a"]
            )
        }
    }

    private static func videoArguments(quality: DownloadVideoQuality) -> YtDlpFormatArguments {
        switch quality {
        case .mp4_360:
            return YtDlpFormatArguments(
                formatSelector: "best[height<=360][ext=mp4]/best[height<=360]/worst"
            )
        case .mp4_720:
            return YtDlpFormatArguments(
                formatSelector: "best[height<=720][ext=mp4]/best[height<=720]/best"
            )
        case .best:
            return YtDlpFormatArguments(formatSelector: "bestvideo*+bestaudio/best")
        }
    }
}
