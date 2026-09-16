import SwiftUI

// MARK: - Shell & panels

/// Window shell background — the canonical semantic shell fill (real primitive, not an alias).
public struct HubShellBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ZStack {
            if !reduceTransparency {
                if #available(macOS 26.0, *) {
                    // Liquid Glass is one chrome-column sheet (`HubGlassBackdrop`), not a
                    // second window-wide material under opaque content.
                    EmptyView()
                } else {
                    HubVisualEffectView(material: .underWindowBackground, blending: .behindWindow)
                }
            }
            HubDesignSystem.Palette.canvas
                .opacity(reduceTransparency ? 1 : 0.82)
            LinearGradient(
                colors: [Color.white.opacity(0.022), Color.white.opacity(0), Color.black.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// Sidebar / nav row selection — the sidebar selection primitive (restyled, NOT deprecated).
public struct HubSidebarNavRow: ViewModifier {
    let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .fill(HubDesignSystem.Palette.selection)
                        .overlay {
                            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                                .strokeBorder(
                                    HubDesignSystem.Palette.selectionStroke.opacity(0.45),
                                    lineWidth: 0.5
                                )
                        }
                }
            }
    }
}

public extension View {
    /// Semantic shell background (real primitive — not deprecated).
    func hubShellBackground() -> some View {
        background(HubShellBackground())
    }

    /// Sidebar nav row selection (real primitive — restyled, not deprecated).
    func hubSidebarNavRow(isSelected: Bool) -> some View {
        modifier(HubSidebarNavRow(isSelected: isSelected))
    }
}
