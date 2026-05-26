import AppCore
import FeatureAudioConverter
import FeatureDownloader
import SwiftUI

struct HelperToolsHealthStrip: View {
    let context: ToolContext

    @State private var ytDlpStatus = HelperStatus(label: "yt-dlp", state: .checking)
    @State private var ffmpegStatus = HelperStatus(label: "FFmpeg", state: .checking)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Helper Tools")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            helperRow(ytDlpStatus)
            helperRow(ffmpegStatus)

            if ytDlpStatus.state.needsSetup || ffmpegStatus.state.needsSetup {
                Text("Install missing helpers with Homebrew to enable downloader and conversion workflows.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refresh()
        }
    }

    private func helperRow(_ status: HelperStatus) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.state.color)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 8)
            Text(status.state.displayText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.label) \(status.state.displayText)")
    }

    private func refresh() async {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        let helperSettings = settings.helperTools

        let ytChecker = YtDlpHealthChecker()
        switch await ytChecker.availability(settings: helperSettings) {
        case .missing:
            ytDlpStatus = HelperStatus(label: "yt-dlp", state: .missing)
        case .available(let version):
            ytDlpStatus = HelperStatus(label: "yt-dlp", state: .available(version: version))
        case .outdated(let current, let minimum):
            ytDlpStatus = HelperStatus(label: "yt-dlp", state: .outdated(current: current, minimum: minimum))
        case .unusable(let message):
            ytDlpStatus = HelperStatus(label: "yt-dlp", state: .unusable(message: message))
        }

        let ffmpegChecker = FFmpegHealthChecker()
        switch await ffmpegChecker.availability(settings: helperSettings) {
        case .missing:
            ffmpegStatus = HelperStatus(label: "FFmpeg", state: .missing)
        case .available(let version):
            ffmpegStatus = HelperStatus(label: "FFmpeg", state: .available(version: version))
        case .unusable(let message):
            ffmpegStatus = HelperStatus(label: "FFmpeg", state: .unusable(message: message))
        }
    }
}

private struct HelperStatus {
    let label: String
    let state: HelperState
}

private enum HelperState {
    case checking
    case available(version: String)
    case missing
    case outdated(current: String, minimum: String)
    case unusable(message: String)

    var displayText: String {
        switch self {
        case .checking:
            return "Checking"
        case .available:
            return "Ready"
        case .missing:
            return "Missing"
        case .outdated:
            return "Update needed"
        case .unusable:
            return "Needs setup"
        }
    }

    var needsSetup: Bool {
        switch self {
        case .missing, .outdated, .unusable:
            return true
        case .checking, .available:
            return false
        }
    }

    var color: Color {
        switch self {
        case .checking:
            return .secondary
        case .available:
            return .green
        case .missing, .unusable:
            return .red
        case .outdated:
            return .orange
        }
    }
}
