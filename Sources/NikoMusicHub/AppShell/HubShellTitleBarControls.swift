import AppCore
import SwiftUI

/// Window-level sidebar toggles aligned with the traffic-light row (Cursor-style).
struct HubShellTitleBarControls: View {
    @ObservedObject var session: HubShellSession

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            HubIconButton(
                systemImage: "sidebar.left",
                accessibilityLabel: session.showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                help: session.showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                isSelected: session.showToolSidebar,
                isToggle: true,
                action: { session.toggleToolSidebar() }
            )

            Spacer(minLength: 0)

            HubIconButton(
                systemImage: "sidebar.right",
                accessibilityLabel: session.showOutputInbox ? "Hide output inbox" : "Show output inbox",
                help: session.showOutputInbox ? "Hide output inbox" : "Show output inbox",
                isSelected: session.showOutputInbox,
                isToggle: true,
                action: { session.toggleOutputInbox() }
            )
        }
        .padding(.leading, HubShellLayout.titleBarLeadingInset)
        .padding(.trailing, HubShellLayout.titleBarTrailingInset)
        .frame(height: HubShellLayout.titleBarHeight)
    }
}
