import SwiftUI

/// Shared tool-pane spacing so every tab aligns with the shell chrome.
public enum HubToolLayout {
    public static let horizontalPadding: CGFloat = 16
    public static let bottomPadding: CGFloat = 16
    public static let topPadding: CGFloat = 20
    public static let sectionSpacing: CGFloat = 20
    public static let maxContentWidth: CGFloat = 680
    public static let headerMinHeight: CGFloat = 56
}

/// Shared shell chrome insets so collapse/expand controls stay in the same place.
public enum HubShellLayout {
    /// Matches `ToolSidebarView` app mark top padding.
    public static let toolSidebarControlTopInset: CGFloat = 34
    /// Matches `OutputInboxInspectorView` outer top padding in `AppShellView`.
    public static let outputInboxControlTopInset: CGFloat = 12 + HubDesignSystem.Spacing.panel
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
