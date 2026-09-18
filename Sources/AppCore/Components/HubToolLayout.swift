import SwiftUI

/// Shared tool-pane spacing so every tab aligns with the shell chrome.
public enum HubToolLayout {
    public static let horizontalPadding: CGFloat = 16
    public static let bottomPadding: CGFloat = 16
    public static let topPadding: CGFloat = 20
    public static let sectionSpacing: CGFloat = 20
    public static let maxContentWidth: CGFloat = 680
    /// Every page header band (tool pages, Board, Archive list, Analytics, Inbox)
    /// is exactly this tall so titles and header actions share one keyline.
    public static let headerHeight: CGFloat = 56
    public static let headerMinHeight: CGFloat = headerHeight

    // Tool-page slot grid. Pages fill the slots in this order and skip the ones
    // they do not have, so equal roles land on equal keylines across tools:
    // header → primary card → field/summary row → chip row → action row.
    /// Drop zones, the tap pad, the capture readout, the URL entry card.
    public static let primaryCardHeight: CGFloat = 168
    /// Preset summary, output-folder row, secondary URL field.
    public static let fieldRowHeight: CGFloat = 44
    /// Gap from a header band to the secondary content row (tool item, search, preview card).
    public static let secondaryRowGap: CGFloat =
        HubDesignSystem.Spacing.sectionHeaderTop + HubDesignSystem.Spacing.sectionHeaderBandHeight
}

/// Shared shell chrome insets for the unified title bar row.
public enum HubShellLayout {
    /// Title-strip height: 36pt of air for the traffic lights + compact 26pt title
    /// controls (Codex strips read ~10pt taller than our old 30pt packing).
    /// Decoupled from `iconButtonSize` (page-header actions stay 30pt).
    public static let titleBarHeight: CGFloat = 36
    /// Leading inset: breathing room between the traffic lights and the first
    /// title-bar button. Clears the repositioned lights (zoom ends ~85) + 14pt gap.
    /// Keep until NMH-128 overlap proof; then migrate toggles to `ToolbarItem(placement: .navigation)`.
    public static let titleBarLeadingInset: CGFloat = 99
    /// Shared vertical axis for the traffic lights and the sidebar row icons
    /// (Codex-like single axis, measured 2026-09-18): sidebar row at x=12 with
    /// 10pt inner padding and an 18pt icon frame centers glyphs at 31pt, so the
    /// window controls are shifted until the close button centers there too.
    /// The system lights sit at ~16pt and cannot take the icons to them (an 18pt
    /// frame inside a 12-inset row bottoms out at a 21pt center), hence this
    /// direction. Not applied in Full Screen (system owns the lights there).
    public static let trafficAxisX: CGFloat =
        12 + 10 + HubDesignSystem.Size.sidebarIconFrame / 2 // 31
    /// Matches the page side inset so title-bar icons sit directly above header actions.
    public static let titleBarTrailingInset: CGFloat = HubToolLayout.horizontalPadding
}

/// `NSWindow.title` for the hidden-title-bar shell (Window menu / Mission Control).
public enum HubMainWindowTitle {
    public static let fallback = "Niko Music Hub"

    public static func resolved(selectedToolID: ToolFeatureID?, registry: ToolRegistry) -> String {
        guard let selectedToolID else { return fallback }
        return registry.feature(for: selectedToolID)?.metadata.displayName ?? fallback
    }
}

public extension View {
    func hubToolContentPadding() -> some View {
        padding(.horizontal, HubToolLayout.horizontalPadding)
            .padding(.bottom, HubToolLayout.bottomPadding)
            .padding(.top, HubToolLayout.topPadding)
    }

    /// Leading-anchored max-width column with shared shell padding, so tool
    /// titles sit on the same keyline as the Board/Archive headers at every
    /// window width (sidebar-driven panes anchor left; centring is for
    /// standalone preference windows).
    func hubToolContentColumn() -> some View {
        hubToolContentPadding()
            .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Standard scrollable tool page scaffold. Keeps headers and content columns in the
/// same place when switching between tools.
public struct HubToolPage<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HubToolLayout.sectionSpacing) {
                content
            }
            .hubToolContentColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
