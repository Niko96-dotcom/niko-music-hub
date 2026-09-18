import AppCore
import SwiftUI

/// Window-level controls aligned with the traffic-light row (Cursor-style):
/// panel toggles, browser-style back/forward, and the active tool's accessory.
struct HubShellTitleBarControls: View {
    /// Codex rhythm: compact 26pt buttons / 13pt glyphs with even 8pt groups
    /// (page-header actions keep the standard 30pt / 14pt toolbar metrics).
    fileprivate static let buttonSize: CGFloat = 26
    fileprivate static let glyphSize: CGFloat = 13
    fileprivate static let groupGap: CGFloat = 8

    @ObservedObject var session: HubShellSession
    var canGoBack = false
    var canGoForward = false
    var toolAccessory: AnyView? = nil
    var onGoBack: () -> Void = {}
    var onGoForward: () -> Void = {}

    var body: some View {
        HStack(spacing: Self.groupGap) {
            // Panel toggles are momentary (no persistent selected card): the panel
            // itself shows the state. A stuck "selected" chip here reads as a bug
            // since the sidebar is visible almost all the time.
            HubIconButton(
                systemImage: "sidebar.leading",
                accessibilityLabel: session.showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar",
                help: session.showToolSidebar ? "Hides the tools column" : "Shows the tools column",
                controlSize: Self.buttonSize,
                glyphSize: Self.glyphSize,
                action: { session.toggleToolSidebar() }
            )

            HStack(spacing: Self.groupGap) {
                HubIconButton(
                    systemImage: "chevron.backward",
                    accessibilityLabel: "Back",
                    help: "Back (⌘[)",
                    isEnabled: canGoBack,
                    controlSize: Self.buttonSize,
                    glyphSize: Self.glyphSize,
                    action: onGoBack
                )
                HubIconButton(
                    systemImage: "chevron.forward",
                    accessibilityLabel: "Forward",
                    help: "Forward (⌘])",
                    isEnabled: canGoForward,
                    controlSize: Self.buttonSize,
                    glyphSize: Self.glyphSize,
                    action: onGoForward
                )
            }

            Spacer(minLength: 0)

            if let toolAccessory {
                toolAccessory
            }

            HubIconButton(
                systemImage: "sidebar.trailing",
                accessibilityLabel: session.showOutputInbox ? "Hide output inbox" : "Show output inbox",
                help: session.showOutputInbox ? "Hides the Output Inbox" : "Shows the Output Inbox",
                controlSize: Self.buttonSize,
                glyphSize: Self.glyphSize,
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
