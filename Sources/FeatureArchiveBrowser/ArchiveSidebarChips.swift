import AppCore
import SwiftUI

/// Flat filter chip (reference: no outline strokes). Selected = `Palette.accentFill` fill +
/// `textPrimary`; unselected = transparent with `textSecondary`, hover white 5%.
struct ArchiveShelfChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(isSelected ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: HubDesignSystem.Size.chipHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(chipFill)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var chipFill: Color {
        if isSelected { return HubDesignSystem.Palette.accentFill }
        return isHovered ? Color.white.opacity(0.05) : Color.clear
    }
}

/// Flat icon-only filter toggle (reference: borderless, hover fill only). Used for the
/// single-glyph browse filters (stems / no-preview / warnings) in place of the deprecated
/// `hubGlassChip`-backed `HubIconButton.archiveBrowseFilter`, which always drew a stroke.
struct ArchiveIconFilterChip: View {
    let systemImage: String
    let accessibilityLabel: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary)
                .frame(width: HubDesignSystem.Size.chipHeight, height: HubDesignSystem.Size.chipHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(chipFill)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "On" : "Off")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chipFill: Color {
        if isSelected { return HubDesignSystem.Palette.accentFill }
        return isHovered ? Color.white.opacity(0.05) : Color.clear
    }
}
