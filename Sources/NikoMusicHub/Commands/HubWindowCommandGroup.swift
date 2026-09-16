import AppKit
import SwiftUI

/// Explicit Window commands for Close / Minimize / Full Screen (NMH-129).
/// With a single `Window`, system Close often stays disabled and still consumes ⌘W.
/// Menu buttons call into `HubWindowChromeActions`, and a local key monitor ensures
/// ⌘W / ⌘M / ⌃⌘F reach those actions.
struct HubWindowCommandGroup: Commands {
    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("Close") {
                HubWindowChromeActions.closeMainWindow()
            }
            .keyboardShortcut("w")

            Button("Minimize") {
                HubWindowChromeActions.minimizeMainWindow()
            }
            .keyboardShortcut("m")

            Button("Enter Full Screen") {
                HubWindowChromeActions.toggleFullScreenMainWindow()
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
        }
    }
}

@MainActor
enum HubWindowChromeActions {
    private static var monitor: Any?
    private static let debugPath = "/tmp/nmh-129-fs-debug.txt"
    private static var fsDebugEnabled: Bool {
        ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_FS_DEBUG"] == "1"
    }

    static func installKeyMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore capsLock/numericPad/function bits — they break exact flag equality.
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if flags == .command, chars == "w" {
                closeMainWindow()
                return nil
            }
            if flags == .command, chars == "m" {
                minimizeMainWindow()
                return nil
            }
            if flags == [.command, .control], chars == "f" {
                toggleFullScreenMainWindow()
                return nil
            }
            return event
        }
    }

    static func mainWindow() -> NSWindow? {
        let mainID = NSUserInterfaceItemIdentifier("hub.main")
        return NSApp.windows.first(where: { $0.identifier == mainID })
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: \.canBecomeMain)
    }

    static func closeMainWindow() {
        guard let target = mainWindow() else { return }
        if target.styleMask.contains(.closable) {
            target.close()
        } else {
            target.orderOut(nil)
        }
    }

    static func minimizeMainWindow() {
        mainWindow()?.miniaturize(nil)
    }

    /// Enumerate every NSWindow for NMH-129 keyWindow diagnosis (fixture GUI only).
    private static func appendDebug(_ text: String) {
        guard fsDebugEnabled, let data = text.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: debugPath) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: debugPath))
        }
    }

    private static func dumpWindows(_ label: String) {
        guard fsDebugEnabled else { return }
        var lines: [String] = []
        lines.append("=== \(label) ===")
        lines.append(
            "appActive=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) "
                + "keyWin=\(describe(NSApp.keyWindow)) mainWin=\(describe(NSApp.mainWindow)) "
                + "modal=\(describe(NSApp.modalWindow)) wins=\(NSApp.windows.count)"
        )
        for (idx, w) in NSApp.windows.enumerated() {
            let cls = NSStringFromClass(type(of: w))
            lines.append(
                "[\(idx)] id=\(w.identifier?.rawValue ?? "nil") class=\(cls) "
                    + "title=\(w.title.prefix(40)) isKey=\(w.isKeyWindow) canKey=\(w.canBecomeKey) "
                    + "canMain=\(w.canBecomeMain) isMain=\(w.isMainWindow) visible=\(w.isVisible) "
                    + "level=\(w.level.rawValue) excluded=\(w.isExcludedFromWindowsMenu) "
                    + "style=\(w.styleMask.rawValue) behavior=\(w.collectionBehavior.rawValue) "
                    + "frame=\(NSStringFromRect(w.frame)) "
                    + "isPanel=\(w is NSPanel) sheet=\(w.attachedSheet != nil) "
                    + "hasParent=\(w.parent != nil) childCount=\(w.childWindows?.count ?? 0)"
            )
        }
        let text = lines.joined(separator: "\n") + "\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugPath),
               let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: debugPath)) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: URL(fileURLWithPath: debugPath))
            }
        }
    }

    private static func describe(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return window.identifier?.rawValue ?? (window.title.isEmpty ? NSStringFromClass(type(of: window)) : window.title)
    }

    /// End SwiftUI sheets / SheetPresentationWindow that block Full Screen.
    /// Fixture dumps showed hub.main with attachedSheet + a key SheetPresentationWindow
    /// (Audio Recorder permission/error sheet) while toggleFullScreen no-ops.
    private static func dismissSheets(on window: NSWindow) {
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
            sheet.orderOut(nil)
        }
        for w in NSApp.windows {
            let cls = NSStringFromClass(type(of: w))
            guard cls.contains("SheetPresentation") || w.isSheet else { continue }
            if let parent = w.sheetParent {
                parent.endSheet(w)
            }
            w.orderOut(nil)
            w.close()
        }
    }

    /// Demote non-main key-capable windows (MenuBarExtra / Settings panels / helpers)
    /// that can leave `NSApp.keyWindow == nil` after AX/menu activation.
    private static func demoteBlockingWindows(except keep: NSWindow) {
        for w in NSApp.windows where w !== keep {
            if w.isKeyWindow {
                w.resignKey()
            }
            let cls = NSStringFromClass(type(of: w))
            let looksStatus =
                cls.localizedCaseInsensitiveContains("Status")
                || cls.localizedCaseInsensitiveContains("MenuBar")
                || (w.styleMask.contains(.borderless) && w.frame.width < 64 && w.frame.height < 64)
            let looksSheet = cls.contains("SheetPresentation") || w.isSheet
            let looksAuxPanel = (w is NSPanel) && !w.isVisible
            if looksStatus || looksAuxPanel {
                w.resignKey()
                if w.isVisible && looksStatus {
                    w.orderBack(nil)
                }
            }
            if looksSheet {
                if let parent = w.sheetParent {
                    parent.endSheet(w)
                }
                w.resignKey()
                w.orderOut(nil)
            }
        }
    }

    private static func forceKey(_ window: NSWindow) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate()

        dismissSheets(on: window)
        demoteBlockingWindows(except: window)

        // SwiftUI marks single Window as excluded; keep main eligible for FS chrome.
        if window.isExcludedFromWindowsMenu {
            window.isExcludedFromWindowsMenu = false
        }

        window.level = .normal
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()

        // SwiftUI host views sometimes need an explicit first responder before isKey sticks.
        if !window.isKeyWindow, let content = window.contentView {
            _ = window.makeFirstResponder(content)
            window.makeKeyAndOrderFront(nil)
            window.makeKey()
        }

        // Last resort: order out other visible key-capable windows (do NOT restore sheets).
        if !window.isKeyWindow {
            let others = NSApp.windows.filter { $0 !== window && $0.isVisible && $0.canBecomeKey }
            for o in others {
                o.orderOut(nil)
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeKey()
        }
    }

    static func toggleFullScreenMainWindow() {
        guard let window = mainWindow() else {
            dumpWindows("toggle-no-main")
            return
        }

        dumpWindows("pre")
        forceKey(window)

        // Reset to the minimal AppKit Full Screen contract (drop SwiftUI extra bits).
        let needed: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        var style = window.styleMask
        style.formUnion(needed)
        // fullSizeContentView + hidden titlebar has been implicated in FS no-ops; drop for toggle.
        style.remove(.fullSizeContentView)
        if window.styleMask != style {
            window.styleMask = style
        }
        window.collectionBehavior = [.managed, .fullScreenPrimary]

        let target = window
        DispatchQueue.main.async {
            forceKey(target)
            dumpWindows("mid")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                forceKey(target)
                dismissSheets(on: target)
                // Probe private enter-FS gate when present (diagnostic only).
                var canEnter = "n/a"
                let sel = NSSelectorFromString("_canEnterFullScreen")
                if target.responds(to: sel) {
                    if let num = target.perform(sel)?.takeUnretainedValue() as? NSNumber {
                        canEnter = String(describing: num.boolValue)
                    } else {
                        canEnter = "responds-no-number"
                    }
                }
                let screenName = target.screen?.localizedName ?? "nil"
                let line =
                    "BEFORE_TOGGLE isKey=\(target.isKeyWindow) keyWin=\(describe(NSApp.keyWindow)) "
                    + "fsBit=\(target.styleMask.contains(.fullScreen)) style=\(target.styleMask.rawValue) "
                    + "behavior=\(target.collectionBehavior.rawValue) canEnter=\(canEnter) "
                    + "screen=\(screenName) screens=\(NSScreen.screens.count)\n"
                appendDebug(line)
                target.toggleFullScreen(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let after =
                        "AFTER style=\(target.styleMask.rawValue) "
                        + "fsBit=\(target.styleMask.contains(.fullScreen)) "
                        + "isKey=\(target.isKeyWindow) frame=\(NSStringFromRect(target.frame))\n"
                    appendDebug(after)
                    dumpWindows("post")
                }
            }
        }
    }
}

