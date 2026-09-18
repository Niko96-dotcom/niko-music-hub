import SwiftUI

// MARK: - Shell & panels

/// Window shell background — the canonical semantic shell fill (real primitive, not an alias).
public struct HubShellBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    public init() {}

    /// Inactive (non-key window) chrome is subdued (NMH-069).
    private var isWindowActive: Bool { controlActiveState == .key }

    public var body: some View {
        ZStack {
            if !reduceTransparency {
                if #available(macOS 26.0, *) {
                    // Liquid Glass is one chrome-column sheet (`HubGlassBackdrop`), not a
                    // second window-wide material under opaque content.
                    EmptyView()
                } else {
                    HubVisualEffectView(
                        material: .underWindowBackground,
                        blending: .behindWindow,
                        isActive: isWindowActive
                    )
                }
            }
            HubDesignSystem.Palette.canvas
                .opacity(reduceTransparency ? 1 : (isWindowActive ? 0.82 : 0.94))
            LinearGradient(
                colors: [
                    Color(HubDynamicColor(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.022))),
                    Color(HubDynamicColor(light: Color.black.opacity(0), dark: Color.white.opacity(0))),
                    Color.black.opacity(0.06),
                ],
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
                    // A selected row reads as a small raised surface, not a flat swatch:
                    // the fill carries a soft vertical sheen, the stroke is brighter along
                    // the top edge (the edge that catches light) and fades toward the
                    // bottom, and a low shadow lifts it off the rail. This is what makes
                    // the state legible without bolding the label.
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .fill(HubDesignSystem.Palette.selection)
                        .overlay {
                            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [HubDesignSystem.Highlight.sheen, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            HubDesignSystem.Highlight.rimStrong,
                                            HubDesignSystem.Highlight.rim,
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: HubDesignSystem.Elevation.low.color,
                            radius: HubDesignSystem.Elevation.low.radius,
                            y: HubDesignSystem.Elevation.low.y
                        )
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
