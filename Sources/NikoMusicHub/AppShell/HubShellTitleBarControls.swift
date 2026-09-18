import AppCore
import SwiftUI

/// Window-level controls aligned with the traffic-light row (Cursor-style):
/// panel toggles, browser-style back/forward, and the active tool's accessory.
struct HubShellTitleBarControls: View {
    @ObservedObject var session: HubShellSession
    var canGoBack = false
    var canGoForward = false
    var toolAccessory: AnyView? = nil
    var onGoBack: () -> Void = {}
    var onGoForward: () -> Void = {}

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            HubIconButton(
                systemImage: "sidebar.leading",
                accessibilityLabel: session.showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                help: session.showToolSidebar ? "Hides the tools column" : "Shows the tools column",
                isSelected: session.showToolSidebar,
                isToggle: true,
                action: { session.toggleToolSidebar() }
            )

            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                HubIconButton(
                    systemImage: "chevron.backward",
                    accessibilityLabel: "Back",
                    help: "Back (⌘[)",
                    isEnabled: canGoBack,
                    action: onGoBack
                )
                .keyboardShortcut("[", modifiers: .command)
                HubIconButton(
                    systemImage: "chevron.forward",
                    accessibilityLabel: "Forward",
                    help: "Forward (⌘])",
                    isEnabled: canGoForward,
                    action: onGoForward
                )
                .keyboardShortcut("]", modifiers: .command)
            }

            Spacer(minLength: 0)

            if let toolAccessory {
                toolAccessory
            }

            HubIconButton(
                systemImage: "sidebar.trailing",
                accessibilityLabel: session.showOutputInbox ? "Hide output inbox" : "Show output inbox",
                help: session.showOutputInbox ? "Hides the Output Inbox" : "Shows the Output Inbox",
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

#if DEBUG
#Preview("Title bar RTL") {
    HubShellTitleBarControls(
        session: HubShellSession(preferences: NMH038PreviewPreferenceStore())
    )
    .environment(\.layoutDirection, .rightToLeft)
    .frame(width: 640, height: HubShellLayout.titleBarHeight)
}

/// Isolated prefs so the RTL preview never writes live defaults.
private struct NMH038PreviewPreferenceStore: PreferenceStore {
    func bool(forKey _: String) -> Bool? { nil }
    func set(_: Bool, forKey _: String) {}
    func data(forKey _: String) -> Data? { nil }
    func set(_: Data, forKey _: String) {}
    func string(forKey _: String) -> String? { nil }
    func set(_: String, forKey _: String) {}
    func removeObject(forKey _: String) {}
}
#endif
