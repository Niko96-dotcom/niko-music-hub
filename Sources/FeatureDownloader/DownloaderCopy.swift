import Foundation

public enum DownloaderCopy {
    public static let toolLabel = "Downloader"
    public static let urlPlaceholder = "Paste a supported URL..."
    public static let checkingURL = "Checking URL..."
    public static let readyToDownload = "Ready to download"
    public static let downloading = "Downloading..."
    public static let downloadComplete = "Downloaded"
    public static let downloadFailed = "Download failed"

    public static let trustNotice = "Downloads are for material you are allowed to access and save."
    public static let sourceLabel = "Source"
    public static let destinationLabel = "Output folder"
    public static let formatLabel = "Download as"
    public static let mediaKindLabel = "Media"
    public static let audioFormatLabel = "Audio format"
    public static let videoQualityLabel = "Video quality"

    public static let missingYtDlp = "yt-dlp is required. Choose yt-dlp in Settings."
    public static func outdatedYtDlp(current: String, minimumExpected: String) -> String {
        "yt-dlp \(current) is outdated (expected \(minimumExpected) or newer). Open Settings → Helper Tools and update yt-dlp with Homebrew, then verify the path."
    }
    public static let unsupportedURL = "This URL is not supported or yt-dlp could not access it."
    public static let downloadFailedError = "Download failed"
    public static let retryableError = "Download failed (will retry): "
    public static let permanentError = "Download failed (permanent): "
    public static let partialCleanup = "Partial download cleaned up."

    public static let download = "Download"
    public static let clear = "Clear"
    public static let showInFinder = "Show in Finder"

    public static let retryInSeconds = "Retrying in"
    public static let attempt = "Attempt"
}