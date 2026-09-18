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
            // Codex-quiet: every row label at full strength, selection carried by
            // the flat gray pill alone — no sheen, rim or shadow (DS-13: never accent).
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .fill(HubDesignSystem.Palette.selection)
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
