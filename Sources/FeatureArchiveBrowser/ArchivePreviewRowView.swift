import AppCore
import AVFoundation
import NikoMusicCore
import SwiftUI

struct ArchivePreviewRowView: View {
    let song: Song
    let candidate: PreviewCandidate
    let isMain: Bool
    let onPlay: () -> Void
    let onSetMain: () -> Void
    let onIgnore: () -> Void
    @ObservedObject private var session = ArchivePreviewSession.shared
    @State private var audioDescription: String?

    private var isLoaded: Bool { session.songID == song.id && session.preview?.id == candidate.id }

    var body: some View {
        HStack(spacing: 12) {
            HubIconButton(systemImage: isLoaded && session.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: "\(isLoaded && session.isPlaying ? "Pause" : "Play") \(candidate.fileName)",
                isEnabled: !session.captureActive, action: onPlay)
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.fileName).font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                    .lineLimit(2).truncationMode(.middle).help(candidate.filePath.path)
                Text(audioDescription ?? metadataFallback)
                    .font(HubDesignSystem.Typography.caption()).foregroundStyle(.secondary)
                if isMain || isLoaded {
                    Text([isMain ? (song.previewSelectionMode == .manual ? "Main" : "Main · Auto") : nil,
                          isLoaded ? (session.isPlaying ? "Playing" : "In player") : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(HubDesignSystem.Typography.micro()).foregroundStyle(HubDesignSystem.Palette.accent)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Button("Compare") { session.compare(song: song, candidate: candidate) }
                    .controlSize(.small)
                    .disabled(session.songID != song.id || isLoaded || session.captureActive)
                    .help("Switch at the same elapsed time. Use aligned bounces.")
                    .accessibilityLabel("Compare \(candidate.fileName)")
                Menu {
                    Button("Set Main", action: onSetMain).disabled(isMain)
                    Button("Ignore preview", action: onIgnore)
                    Text(candidate.filePath.path)
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Actions for \(candidate.fileName)")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(isLoaded ? HubDesignSystem.Palette.selection.opacity(0.5) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .task(id: "\(candidate.id)|\(candidate.modifiedAt.timeIntervalSince1970)") {
            audioDescription = nil
            let url = candidate.filePath
            let result = await Task.detached(priority: .utility) {
                guard let file = try? AVAudioFile(forReading: url) else { return nil as String? }
                let format = file.fileFormat
                let description = format.streamDescription.pointee
                let seconds = Double(file.length) / format.sampleRate
                var parts = [ArchiveAudioMetadata.durationLabel(seconds), url.pathExtension.uppercased()]
                if description.mBitsPerChannel > 0 { parts.append("\(description.mBitsPerChannel)-bit") }
                parts.append("\(String(format: "%g", format.sampleRate / 1000)) kHz")
                return parts.joined(separator: " · ")
            }.value
            guard !Task.isCancelled else { return }
            audioDescription = result
        }
    }

    private var metadataFallback: String {
        [candidate.durationSeconds.map(ArchiveAudioMetadata.durationLabel), candidate.fileExtension.uppercased()]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private enum ArchiveAudioMetadata {
    nonisolated static func durationLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
    }
}
