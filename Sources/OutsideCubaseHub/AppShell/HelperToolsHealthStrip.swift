import AppCore
import FeatureAudioConverter
import FeatureDownloader
import SwiftUI

struct HelperToolsHealthStrip: View {
    let context: ToolContext

    @State private var ytDlpLine = "yt-dlp: checking…"
    @State private var ffmpegLine = "FFmpeg: checking…"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Helper Tools")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(ytDlpLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(ffmpegLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        let helperSettings = settings.helperTools

        let ytChecker = YtDlpHealthChecker()
        switch await ytChecker.availability(settings: helperSettings) {
        case .missing:
            ytDlpLine = "yt-dlp: not found — install via Homebrew (brew install yt-dlp)"
        case .available(let version):
            let path = (helperSettings.ytDlp ?? YtDlpHealthChecker.detectYtDlp())?.path ?? "yt-dlp"
            ytDlpLine = "yt-dlp: \(version) at \(path)"
        case .outdated(let current, let minimum):
            ytDlpLine = "yt-dlp: \(current) (expected \(minimum)+)"
        case .unusable(let message):
            ytDlpLine = "yt-dlp: unusable — \(message)"
        }

        let ffmpegChecker = FFmpegHealthChecker()
        switch await ffmpegChecker.availability(settings: helperSettings) {
        case .missing:
            ffmpegLine = "FFmpeg: not found — install via Homebrew (brew install ffmpeg)"
        case .available(let version):
            let path = (helperSettings.ffmpeg ?? FFmpegHealthChecker.detectFfmpeg())?.path ?? "ffmpeg"
            ffmpegLine = "FFmpeg: \(version) at \(path)"
        case .unusable(let message):
            ffmpegLine = "FFmpeg: unusable — \(message)"
        }
    }
}
