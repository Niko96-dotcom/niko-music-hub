import SwiftUI

/// Shared tool-pane spacing so every tab aligns with the shell chrome.
public enum HubToolLayout {
    public static let horizontalPadding: CGFloat = 24
    public static let bottomPadding: CGFloat = 24
    public static let topPadding: CGFloat = 16
    public static let sectionSpacing: CGFloat = 24
    public static let maxContentWidth: CGFloat = 680
}

public extension View {
    func hubToolContentPadding() -> some View {
        padding(.horizontal, HubToolLayout.horizontalPadding)
            .padding(.bottom, HubToolLayout.bottomPadding)
            .padding(.top, HubToolLayout.topPadding)
    }
}
