import AppCore
import SwiftUI

/// The shell mounts this once, outside the cached tool panes. It shows the archive
/// view model's preview session.
public struct ArchivePersistentPlayerView: View {
    @ObservedObject private var session: ArchivePreviewSession
    @ObservedObject private var player: ArchivePreviewPlayer
    let onOpenSong: () -> Void

    public init(viewModel: ArchiveBrowserViewModel, onOpenSong: @escaping () -> Void) {
        _session = ObservedObject(wrappedValue: viewModel.previewSession)
        _player = ObservedObject(wrappedValue: viewModel.previewSession.player)
        self.onOpenSong = onOpenSong
    }

    public var body: some View {
        if let preview = session.preview {
            let canSkip = player.duration > 0
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 16) {
                    Button {
                        session.player.seekRelative(-5, url: preview.filePath)
                    } label: {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                            .frame(width: 28, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSkip)
                    .accessibilityLabel("Skip back 5 seconds")

                    Button { session.toggle() } label: {
                        Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HubDesignSystem.Palette.canvas)
                            .frame(width: 34, height: 34)
                            .background(HubDesignSystem.Palette.textPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.captureActive)
                    .accessibilityLabel(session.isPlaying ? "Pause preview" : "Play preview")

                    Button {
                        session.player.seekRelative(5, url: preview.filePath)
                    } label: {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                            .frame(width: 28, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSkip)
                    .accessibilityLabel("Skip forward 5 seconds")

                    Button {
                        session.openSong()
                        onOpenSong()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.songTitle).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                            Text(session.captureActive ? "Paused for recording" : (session.player.playbackError ?? preview.fileName))
                                .font(.system(size: 10))
                                .foregroundStyle(session.player.playbackError == nil ? HubDesignSystem.Palette.textSecondary : HubDesignSystem.Palette.warning)
                        }
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 120, idealWidth: 260, maxWidth: 300, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(preview.fileName)
                    .accessibilityLabel("Open playing song: \(session.songTitle)")

                    ArchivePreviewProgressView(
                        position: player.position, player: player, url: preview.filePath,
                        duration: player.duration, isLoading: player.isLoading
                    )
                    Text(Self.time(session.player.duration)).monospacedDigit()
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
                    Slider(value: $session.volume, in: 0...1)
                        .frame(width: 64).controlSize(.mini).accessibilityLabel("Preview volume")
                }
                .padding(.horizontal, 24)
                .frame(height: 72)
                .background(HubDesignSystem.Palette.canvas)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Persistent preview player")
        }
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds)
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

/// The elapsed time and the position slider: the only views that follow the play
/// position, so a playing preview re-renders these and not the bar or the board.
private struct ArchivePreviewProgressView: View {
    @ObservedObject var position: ArchivePreviewPosition
    let player: ArchivePreviewPlayer
    let url: URL
    let duration: Double
    let isLoading: Bool

    var body: some View {
        Text(ArchivePersistentPlayerView.time(position.seconds)).monospacedDigit()
            .font(.system(size: 10)).foregroundStyle(.secondary)
        Slider(value: Binding(
            get: { min(position.seconds, max(duration, 1)) },
            set: { player.seek(to: $0, url: url) }
        ), in: 0...max(duration, 1))
        .disabled(duration <= 0 || isLoading)
        .controlSize(.small)
        .accessibilityLabel("Preview position")
    }
}
