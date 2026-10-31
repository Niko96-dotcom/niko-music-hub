import AppCore
import SwiftUI

struct ArchiveCardPlayButton: View {
    let title: String
    let isPlaying: Bool
    let isLoaded: Bool
    let isEnabled: Bool
    /// Hit target side. Board rows use a smaller one than list rows.
    var size: CGFloat = 44
    /// False hides only the glyph: the button keeps its place, its click and its
    /// accessibility element.
    var showsGlyph = true
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
                .opacity(showsGlyph ? 1 : 0)
                .animation(reduceMotion || scrollActivity?.isScrolling == true ? nil : ArchiveBoardMotion.hover,
                           value: isHovered)
                .animation(reduceMotion || scrollActivity?.isScrolling == true ? nil : ArchiveBoardMotion.hover,
                           value: showsGlyph)
                .frame(width: size, height: size)
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
