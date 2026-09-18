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
    /// Height reserved for traffic lights + sidebar toggle row (matches toolbar icon buttons).
    public static let titleBarHeight: CGFloat = HubDesignSystem.Size.iconButtonSize
    /// Leading inset so toggles sit immediately after the traffic lights.
    /// Keep until NMH-128 overlap proof; then migrate toggles to `ToolbarItem(placement: .navigation)`.
    public static let titleBarLeadingInset: CGFloat = 78
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
