import SwiftUI

// MARK: - Shell & panels

/// Window shell background — the canonical semantic shell fill (real primitive, not an alias).
///
/// Content base, deliberately opaque (HIG Materials: the content layer stays
/// opaque; the frosted material is per chrome column in `HubGlassBackdrop`). The
/// canvas veil + static gradient below are the opaque content base under the
/// column seams; they never overlay the chrome material.
public struct HubShellBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            // The chrome columns paint their own `.sidebar` vibrancy and the content
            // column its own opaque canvas, so this base only shows at the column
            // seams: keep it a plain opaque canvas (no second window-wide material).
            HubDesignSystem.Palette.canvas
                .opacity(shellOpacity)
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

    /// Window-base veil: opaque. Since the title row lives inside the columns
    /// (no full-width strip), nothing refracts through this base any more.
    private var shellOpacity: Double { 1 }
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
