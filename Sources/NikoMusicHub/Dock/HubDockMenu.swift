import AppCore
import AppKit
import SwiftUI

enum HubMainWindow {
    static let windowID = "main"
    static let revealNotification = Notification.Name("NikoMusicHub.revealMainWindow")

    @MainActor
    static func reveal() {
        NotificationCenter.default.post(name: revealNotification, object: nil)
        NSApp.activate()
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}

/// AppKit Dock menu: Open, Archive Browser + production tools, Output Inbox. No Settings, no Quit.
enum HubDockMenu {
    static func make(
        registry: ToolRegistry,
        target: AnyObject,
        openApp: Selector,
        openTool: Selector,
        revealInbox: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        for (index, entry) in MenuBarMenuModel.dockEntries(registry: registry).enumerated() {
            if index == 1 || (index > 1 && isInbox(entry)) {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(title: entry.label, action: nil, keyEquivalent: "")
            item.target = target
            switch entry.command {
            case .openApp:
                item.action = openApp
            case .openTool:
                item.action = openTool
                item.representedObject = entry.id
            case .revealOutputInbox:
                item.action = revealInbox
            default:
                continue
            }
            menu.addItem(item)
        }
        return menu
    }

    private static func isInbox(_ entry: QuickAccessEntry) -> Bool {
        if case .revealOutputInbox = entry.command { return true }
        return false
    }
}

struct HubRevealMainWindowModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: HubMainWindow.revealNotification)) { _ in
            openWindow(id: HubMainWindow.windowID)
            NSApp.activate()
        }
    }
}

extension View {
    func hubOpensMainWindowFromDock() -> some View {
        modifier(HubRevealMainWindowModifier())
    }
}
