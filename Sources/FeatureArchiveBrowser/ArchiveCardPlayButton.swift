import AppCore
import SwiftUI

struct ArchiveCardPlayButton: View {
    let title: String
    let isPlaying: Bool
    let isLoaded: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered || isLoaded
                    ? HubDesignSystem.Palette.textPrimary
                    : HubDesignSystem.Palette.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(!isEnabled)
        .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(title)")
    }
}
