import AppCore
import SwiftUI

struct ArchiveCardPlayButton: View {
    let title: String
    let isPlaying: Bool
    let isLoaded: Bool
    let isEnabled: Bool
    var hoverTarget: ArchiveBoardHoverTarget? = nil
    var scrollActivity: ArchiveBoardScrollActivity? = nil
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered || isLoaded
                    ? HubDesignSystem.Palette.textPrimary
                    : HubDesignSystem.Palette.textSecondary)
                .animation(reduceMotion || scrollActivity?.isScrolling == true ? nil : ArchiveBoardMotion.hover,
                           value: isHovered)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover {
            ArchiveBoardScrollActivity.updateHover($0, target: hoverTarget, isHovered: $isHovered, activity: scrollActivity)
        }
        .disabled(!isEnabled)
        .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(title)")
    }
}
