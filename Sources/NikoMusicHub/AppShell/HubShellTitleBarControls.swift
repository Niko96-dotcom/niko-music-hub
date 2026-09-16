import AppCore
import SwiftUI

/// Window-level sidebar toggles aligned with the traffic-light row (Cursor-style).
struct HubShellTitleBarControls: View {
    @ObservedObject var session: HubShellSession

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            HubIconButton(
                systemImage: "sidebar.leading",
                accessibilityLabel: session.showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                help: session.showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                isSelected: session.showToolSidebar,
                isToggle: true,
                action: { session.toggleToolSidebar() }
            )

            Spacer(minLength: 0)

            HubIconButton(
                systemImage: "sidebar.trailing",
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
