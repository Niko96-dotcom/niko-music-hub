import AppCore
import AppKit
import SwiftUI

/// Tools menu: switch the main-window tool with the sidebar hidden (NMH-013).
struct HubToolsCommands: Commands {
    let registry: ToolRegistry
    let router: QuickAccessRouter
    @ObservedObject var session: HubShellSession

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu("Tools") {
            ForEach(HubToolsShortcutMap.menuMetadata(from: registry.metadata), id: \.id) { metadata in
                toolMenuItem(metadata)
            }
        }
    }

    @ViewBuilder
    private func toolMenuItem(_ metadata: ToolMetadata) -> some View {
        if metadata.id == HubToolsShortcutMap.settingsToolID {
            Divider()
            Button(metadata.displayName) {
                openSettings()
            }
        } else {
            let toolID = metadata.id
            Toggle(metadata.displayName, isOn: Binding(
                get: { session.selectedToolID == toolID },
                set: { _ in
                    router.execute(.openTool(toolID))
                    openWindow(id: "main")
                    NSApp.activate()
                }
            ))
            .hubToolsCommandDigit(HubToolsShortcutMap.keyEquivalent(for: toolID, in: registry.metadata))
        }
    }
}

private extension View {
    @ViewBuilder
    func hubToolsCommandDigit(_ key: KeyEquivalent?) -> some View {
        if let key {
            self.keyboardShortcut(key, modifiers: .command)
        } else {
            self
        }
    }
}
