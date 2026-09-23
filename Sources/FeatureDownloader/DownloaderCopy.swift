import Foundation

public enum DownloaderCopy {
    public static let toolLabel = "Downloader"
    public static let urlPlaceholder = "Paste a supported URL…"
    public static let idleSubtitle = ""
    public static let checkingURL = "Checking URL…"
    public static let readyToDownload = ""
    public static let downloading = "Downloading…"
    public static let convertingAudio = "Converting audio…"
    public static let mergingFormats = "Merging audio and video…"
    public static let convertingVideo = "Converting video…"
    public static let finishingFile = "Finishing file…"
    /// Status while yt-dlp runs a post-processor (`step` is its key).
    public static func postProcessingStatus(step: String) -> String {
        switch step {
        case "ExtractAudio": return convertingAudio
        case "Merger": return mergingFormats
        case "VideoConvertor", "VideoRemuxer": return convertingVideo
        default: return finishingFile
        }
    }
    public static let downloadComplete = "Downloaded"
    public static let downloadFailed = "Download failed"
    public static let downloadCanceled = "Download canceled"
    public static let downloadCanceledDetail = "Download canceled. The Output Inbox was not updated."

    public static let trustNotice = "Downloads are for material you are allowed to access and save."
    public static let sourceLabel = "Source"
    public static let destinationLabel = "Output folder"
    public static let formatLabel = "Download as"
    public static let mediaKindLabel = "Media"
    public static let audioFormatLabel = "Audio format"
    public static let videoQualityLabel = "Video quality"

    public static let missingYtDlp = "yt-dlp is required. Choose yt-dlp in Settings → Helpers."
    public static let ytDlpMissing = "yt-dlp is not installed. Use Install Tools to add it."
    public static func outdatedYtDlp(current: String, minimumExpected: String) -> String {
        "yt-dlp \(current) is outdated (expected \(minimumExpected) or newer). Use Install Tools to update it."
    }
    public static let unsupportedURL = "This URL is not supported or yt-dlp could not access it."
    public static let downloadFailedError = "Download failed"
    public static let retryableError = "Download failed (will retry): "
    public static let permanentError = "Download failed (permanent): "
    /// NMH-141 (TOOL-30): informational status when yt-dlp skips because the
    /// file is already in the Output Inbox. Sentence case, no alert.
    public static let alreadyExistsInInbox = "This file already exists in the Output Inbox."
    public static let partialCleanup = "Partial download cleaned up."
    public static func outputInboxHandoffWarning(_ reason: String) -> String {
        "Downloaded, but Output Inbox could not save the handoff. \(reason)"
    }

    public static let download = "Download"
    public static let clear = "Clear"
    public static let showInFinder = "Show in Finder"

    public static let retryInSeconds = "Retrying in"
    public static let attempt = "Attempt"
}
