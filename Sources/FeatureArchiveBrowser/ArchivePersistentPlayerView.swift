import AppCore
import SwiftUI

/// The shell mounts this once, outside the cached tool panes.
public struct ArchivePersistentPlayerView: View {
    @ObservedObject private var session = ArchivePreviewSession.shared
    @ObservedObject private var player = ArchivePreviewSession.shared.player
    let onOpenSong: () -> Void

    public init(onOpenSong: @escaping () -> Void) { self.onOpenSong = onOpenSong }

    public var body: some View {
        if let preview = session.preview {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 16) {
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

                    Text(Self.time(session.player.currentTime)).monospacedDigit()
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { min(session.player.currentTime, max(session.player.duration, 1)) },
                        set: { session.player.seek(to: $0, url: preview.filePath) }
                    ), in: 0...max(session.player.duration, 1))
                    .disabled(session.player.duration <= 0 || session.player.isLoading)
                    .controlSize(.small)
                    .accessibilityLabel("Preview position")
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
