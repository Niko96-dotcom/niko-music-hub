import AppCore
import SwiftUI

/// Window-level sidebar toggles aligned with the traffic-light row (Cursor-style).
struct HubShellTitleBarControls: View {
    let showToolSidebar: Bool
    let showOutputInbox: Bool
    let onToggleToolSidebar: () -> Void
    let onToggleOutputInbox: () -> Void

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            HubIconButton(
                systemImage: "sidebar.left",
                accessibilityLabel: showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                help: showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                isSelected: showToolSidebar,
                isToggle: true,
                action: onToggleToolSidebar
            )

            Spacer(minLength: 0)

            HubIconButton(
                systemImage: "sidebar.right",
                accessibilityLabel: showOutputInbox ? "Hide output inbox" : "Show output inbox",
                help: showOutputInbox ? "Hide output inbox" : "Show output inbox",
                isSelected: showOutputInbox,
                isToggle: true,
                action: onToggleOutputInbox
            )
        }
        .padding(.leading, HubShellLayout.titleBarLeadingInset)
        .padding(.trailing, HubShellLayout.titleBarTrailingInset)
        .frame(height: HubShellLayout.titleBarHeight)
    }
}
