import SwiftUI

/// Shared tool-pane spacing so every tab aligns with the shell chrome.
public enum HubToolLayout {
    public static let horizontalPadding: CGFloat = 16
    public static let bottomPadding: CGFloat = 16
    public static let topPadding: CGFloat = 20
    public static let sectionSpacing: CGFloat = 20
    public static let maxContentWidth: CGFloat = 680
    public static let headerMinHeight: CGFloat = 56
    /// Gap from a header band to the secondary content row (tool item, search, preview card).
    public static let secondaryRowGap: CGFloat =
        HubDesignSystem.Spacing.sectionHeaderTop + HubDesignSystem.Spacing.sectionHeaderBandHeight
}

/// Shared shell chrome insets for the unified title bar row.
public enum HubShellLayout {
    /// Height reserved for traffic lights + sidebar toggle row (matches toolbar icon buttons).
    public static let titleBarHeight: CGFloat = HubDesignSystem.Size.iconButtonSize
    /// Leading inset so toggles sit immediately after the traffic lights.
    public static let titleBarLeadingInset: CGFloat = 78
    public static let titleBarTrailingInset: CGFloat = 12
}

public extension View {
    func hubToolContentPadding() -> some View {
        padding(.horizontal, HubToolLayout.horizontalPadding)
            .padding(.bottom, HubToolLayout.bottomPadding)
            .padding(.top, HubToolLayout.topPadding)
    }

    /// Centers tool content in a max-width column with shared shell padding (spec §4.2).
    func hubToolContentColumn() -> some View {
        hubToolContentPadding()
            .frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
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
