import SwiftUI

/// Shared tool-pane spacing so every tab aligns with the shell chrome.
public enum HubToolLayout {
    public static let horizontalPadding: CGFloat = 16
    public static let bottomPadding: CGFloat = 16
    public static let topPadding: CGFloat = 12
    public static let sectionSpacing: CGFloat = 20
    public static let maxContentWidth: CGFloat = 640
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
