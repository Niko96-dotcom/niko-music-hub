import SwiftUI

// MARK: - Shell & panels

/// Window shell background — the canonical semantic shell fill (real primitive, not an alias).
///
/// Content base, deliberately NOT glass (HIG Materials: content layer stays opaque /
/// standard materials; Liquid Glass is the functional chrome layer only). On macOS 26
/// the single glass sheet lives in `HubGlassBackdrop` per chrome column — this view
/// contributes no second window-wide material under the opaque content (the `EmptyView`
/// branch). On macOS 14/15 it contributes real AppKit vibrancy
/// (`.underWindowBackground` / `.behindWindow`, a pre-Tahoe system material, not Liquid
/// Glass). The canvas veil + static gradient below are the opaque content base, in a
/// different column from the chrome glass, so they never overlay or dull it.
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
                    // second window-wide material under opaque content. Base stays
                    // transparent so key-window chrome refracts the desktop (LIQUID-KEY).
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

    /// Window-base veil. macOS 26 + key: low — the content column is opaque on its
    /// own, so this only dims the title strip (legibility over busy wallpaper) and
    /// tints what the chrome glass refracts. Inactive / Reduce Transparency: fully
    /// opaque — unfocused chrome goes solid like the Codex sidebar (LIQUID-KEY).
    private var shellOpacity: Double {
        if reduceTransparency { return 1 }
        if #available(macOS 26.0, *) {
            return isWindowActive ? 0.28 : 1.0
        } else {
            return isWindowActive ? 0.82 : 0.94
        }
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
