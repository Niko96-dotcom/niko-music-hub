import AppCore
@testable import FeatureArchiveBrowser
import AppKit
import Foundation
import NikoMusicCore
import SwiftUI
import XCTest

/// Regression for native Edit → Undo staying disabled after a board status
/// change. The main window is not document-based and SwiftUI's
/// `EnvironmentValues.undoManager` is get-only (nil here), so the old
/// `.environment(\.undoManager, …)` write neither compiled nor wired
/// anything. The view model owns the stack and `ArchiveWorkflowUndoBridge`
/// splices an `ArchiveWorkflowUndoChainResponder` into `window.nextResponder`
/// while this pane is the active tool. Registrations target the weak
/// `workflowUndoTarget` proxy, never the view model itself.
@MainActor
final class ArchiveWorkflowUndoWiringTests: XCTestCase {
    func testOwnedManagerIsDefaultWithoutInjection() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        // Production path: no injected manager.
        XCTAssertNil(viewModel.injectedWorkflowUndoManager)
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)
        XCTAssertTrue(owned === viewModel.ownedWorkflowUndoManager)
        XCTAssertFalse(owned.canUndo)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
        XCTAssertTrue(owned.canUndo)
        XCTAssertEqual(owned.undoActionName, "Change Workflow Status")

        owned.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus)
        XCTAssertTrue(owned.canRedo)

        owned.redo()
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    func testOwnedManagerRevokesQueuedDoneBeforeExecution() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        _ = try fixture.addSong(named: "Second Project", extension: "cpr")
        let runtime = BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let first = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Second Project" })
        let execGate = BoundArchiveAuthorizationTests.CaptureGate()
        runtime.archiveAuthImpl = { song, _, _ in
            if song.id == first.id {
                await execGate.enterAndWait()
                return BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime.makeSnapshot(for: song)
            }
            return BoundArchiveAuthorizationTests.DeterministicBoundVaultRuntime.makeSnapshot(for: song)
        }

        // Occupy the transfer slot so the Done request stays queued.
        viewModel.requestArchiveNow(for: first)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultActiveOperation?.songID == first.id }

        // Production path: Done registers on the owned stack (no injection).
        viewModel.requestWorkflowDoneArchive(for: second)
        try await waitUntil { viewModel.pendingArchiveConfirmation != nil }
        viewModel.confirmPendingArchive()
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }) }
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus, .done)
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)
        XCTAssertEqual(owned.undoActionName, "Mark Done")

        owned.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == second.id })?.workflowStatus)
        XCTAssertFalse(viewModel.projectVaultPendingOperations.contains(where: { $0.songID == second.id }))

        await execGate.open()
        try await waitUntil(timeout: .seconds(5)) { viewModel.projectVaultBusySongIDs.isEmpty }
        XCTAssertTrue(runtime.authCalls.filter { $0.songID == second.id }.isEmpty)
        XCTAssertTrue(runtime.copyCalls.filter { $0.songID == second.id }.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.folderPath.path))
        let queuedMessage = viewModel.projectVaultOperationMessages[second.id]
        XCTAssertTrue(queuedMessage?.contains("No project files were changed") == true)
    }

    func testUndoAfterFolderRemovalDoesNotRecreateFolder() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)

        // Simulate an archived-and-removed Active folder.
        try FileManager.default.removeItem(at: song.folderPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: song.folderPath.path))

        let owned = try XCTUnwrap(viewModel.workflowUndoManager)
        owned.undo()
        XCTAssertNil(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus)
        // Undo restores status only; it never recreates deleted folders.
        XCTAssertFalse(FileManager.default.fileExists(atPath: song.folderPath.path))
    }

    // MARK: - Native bridge wiring (runtime evidence, not source mirroring)

    /// The illegal write must stay gone: `EnvironmentValues.undoManager` is
    /// get-only in the installed SDK, so `.environment(\.undoManager, …)`
    /// fails type-check. Raw strings keep the single-backslash keypath
    /// literal exact with no escape ambiguity.
    func testIllegalEnvironmentUndoManagerWriteIsAbsent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func read(_ relative: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        }
        let browser = try read("Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift")
        XCTAssertFalse(browser.contains(#".environment(\.undoManager"#))
        XCTAssertTrue(browser.contains("ArchiveWorkflowUndoBridge"))
        XCTAssertTrue(browser.contains("isActiveTool"))

        let metadata = try read("Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+Metadata.swift")
        XCTAssertTrue(metadata.contains("withTarget: workflowUndoTarget"))
        XCTAssertFalse(metadata.contains("withTarget: self"))

        let bridge = try read("Sources/FeatureArchiveBrowser/ArchiveWorkflowUndoBridge.swift")
        XCTAssertTrue(bridge.contains("window.nextResponder"))
        XCTAssertTrue(bridge.contains("validateUserInterfaceItem"))
        XCTAssertTrue(bridge.contains("isTextEditing"))
        // Window-manager binding is the primary native route (foreground:
        // AppKitWindow answers undo: itself); the chain responder stays only
        // as the manager-less fallback.
        XCTAssertTrue(bridge.contains("boundWindowUndoManager"))
        XCTAssertFalse(bridge.contains("addLocalMonitorForEvents"))
        XCTAssertFalse(bridge.contains("addGlobalMonitorForEvents"))
    }

    /// Active responder exposes the owned stack through the native validation
    /// entry points and drives undo/redo through it.
    func testBridgeResponderDrivesNativeUndoValidation() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)

        let responder = ArchiveWorkflowUndoChainResponder()
        responder.viewModel = viewModel
        responder.isActive = true
        XCTAssertTrue(responder.scopedUndoManager === owned)

        let undoItem = NSMenuItem(title: "Undo", action: #selector(ArchiveWorkflowUndoChainResponder.undo(_:)), keyEquivalent: "")
        let redoItem = NSMenuItem(title: "Redo", action: #selector(ArchiveWorkflowUndoChainResponder.redo(_:)), keyEquivalent: "")
        XCTAssertFalse(responder.validateMenuItem(undoItem))
        XCTAssertFalse(responder.validateUserInterfaceItem(undoItem))

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(owned.canUndo)
        XCTAssertTrue(responder.scopedUndoManager === owned)
        XCTAssertTrue(responder.validateMenuItem(undoItem))
        XCTAssertTrue(responder.validateUserInterfaceItem(undoItem))

        responder.undo(nil)
        XCTAssertNil(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus)
        XCTAssertTrue(responder.validateMenuItem(redoItem))

        responder.redo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// A mounted-but-inactive pane (another tool showing) provides no stack:
    /// validation fails and `undo:` is a no-op.
    func testBridgeResponderInactiveProvidesNoUndo() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)

        let responder = ArchiveWorkflowUndoChainResponder()
        responder.viewModel = viewModel
        responder.isActive = false

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(owned.canUndo)
        XCTAssertNil(responder.scopedUndoManager)
        let undoItem = NSMenuItem(title: "Undo", action: #selector(ArchiveWorkflowUndoChainResponder.undo(_:)), keyEquivalent: "")
        XCTAssertFalse(responder.validateMenuItem(undoItem))
        XCTAssertFalse(responder.validateUserInterfaceItem(undoItem))

        responder.undo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// Text editing keeps the field editor's undo: the bridge yields nil
    /// while editing and recovers the stack otherwise.
    func testBridgeResponderDefersToTextEditing() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)

        let responder = ArchiveWorkflowUndoChainResponder()
        responder.viewModel = viewModel
        responder.isActive = true
        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(owned.canUndo)

        responder.isTextEditingOverride = true
        XCTAssertNil(responder.scopedUndoManager)
        let undoItem = NSMenuItem(title: "Undo", action: #selector(ArchiveWorkflowUndoChainResponder.undo(_:)), keyEquivalent: "")
        XCTAssertFalse(responder.validateMenuItem(undoItem))
        responder.undo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)

        responder.isTextEditingOverride = false
        XCTAssertTrue(responder.scopedUndoManager === owned)
        XCTAssertTrue(responder.validateMenuItem(undoItem))

        responder.isTextEditingOverride = nil
        responder.hostWindow = nil
        XCTAssertTrue(responder.scopedUndoManager === owned)
    }

    /// Window lifecycle: attach splices `window.nextResponder` without
    /// touching the delegate; removal restores the previous chain.
    func testBridgeViewSplicesWindowChainWithoutTouchingDelegate() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let stub = StubArchiveUndoWindowDelegate()
        window.delegate = stub
        let originalNext = window.nextResponder

        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: nil, isActive: true)
        window.contentView?.addSubview(bridge)
        XCTAssertTrue(window.nextResponder === bridge.chainResponder)
        XCTAssertTrue(window.delegate === stub)
        if let originalNext {
            XCTAssertTrue(bridge.chainResponder.nextResponder === originalNext)
        } else {
            XCTAssertNil(bridge.chainResponder.nextResponder)
        }

        bridge.removeFromSuperview()
        if let originalNext {
            XCTAssertTrue(window.nextResponder === originalNext)
        } else {
            XCTAssertNil(window.nextResponder)
        }
        XCTAssertTrue(window.delegate === stub)
        XCTAssertNil(bridge.chainResponder.nextResponder)
    }

    /// `responds(to:)` gating: an inactive, text-editing, or empty-stack
    /// bridge never claims `undo:`/`redo:`, so AppKit continues past it
    /// instead of locking on and disabling the menu.
    func testBridgeResponderGatesRespondsToPreserveDownstream() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)
        let undoSel = #selector(ArchiveWorkflowUndoChainResponder.undo(_:))
        let redoSel = #selector(ArchiveWorkflowUndoChainResponder.redo(_:))

        let responder = ArchiveWorkflowUndoChainResponder()
        responder.viewModel = viewModel
        responder.isActive = false
        responder.isTextEditingOverride = false
        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(owned.canUndo)
        XCTAssertFalse(responder.responds(to: undoSel))

        responder.isActive = true
        responder.isTextEditingOverride = true
        XCTAssertFalse(responder.responds(to: undoSel))

        responder.isTextEditingOverride = false
        XCTAssertTrue(responder.responds(to: undoSel))
        XCTAssertFalse(responder.responds(to: redoSel))

        responder.undo(nil)
        XCTAssertFalse(responder.responds(to: undoSel))
        XCTAssertTrue(responder.responds(to: redoSel))
    }

    /// Native menu titles follow the stack's action name (HIG), not generic
    /// "Undo"/"Redo".
    func testBridgeValidationAppliesNativeMenuTitles() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)

        let responder = ArchiveWorkflowUndoChainResponder()
        responder.viewModel = viewModel
        responder.isActive = true
        responder.isTextEditingOverride = false
        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(owned.canUndo)

        let undoItem = NSMenuItem(title: "Undo", action: #selector(ArchiveWorkflowUndoChainResponder.undo(_:)), keyEquivalent: "")
        XCTAssertTrue(responder.validateMenuItem(undoItem))
        XCTAssertEqual(undoItem.title, owned.undoMenuItemTitle)
        XCTAssertTrue(undoItem.title.contains("Change Workflow Status"))

        responder.undo(nil)
        let redoItem = NSMenuItem(title: "Redo", action: #selector(ArchiveWorkflowUndoChainResponder.redo(_:)), keyEquivalent: "")
        XCTAssertTrue(responder.validateMenuItem(redoItem))
        XCTAssertEqual(redoItem.title, owned.redoMenuItemTitle)
    }

    /// End-to-end through the WINDOW's own manager (not a direct owned-stack
    /// call, not a bridge-classname assertion).
    ///
    /// Live, the key window resolves `first=AppKitWindow
    /// target=AppKitWindow`: SwiftUI's window answers `undo:` itself, so a
    /// responder behind `window.nextResponder` is never consulted and
    /// `NSApp.target(forAction:)` headless assertions (nil target, failed
    /// `sendAction`) cannot prove anything either way. The native target may
    /// legitimately REMAIN the window; what matters is end behavior — the
    /// workflow registration lands on the window's manager and the window's
    /// own `undo:`/`redo:` (exactly what `AppKitWindow.undo:` drives)
    /// perform the status undo/redo. `StubUndoWindow` mimics that window
    /// behavior with a real `NSWindow.undoManager`.
    func testWindowManagerBindingPerformsWorkflowUndoEndToEnd() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = viewModel.ownedWorkflowUndoManager

        let window = StubUndoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        // Replicate the SwiftUI hosting layer between the content view and the
        // zero-size bridge background view.
        let hosting = NSHostingView(rootView: Color.clear)
        window.contentView?.addSubview(hosting)
        hosting.frame = window.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]

        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: true)
        hosting.addSubview(bridge)
        bridge.attachIfNeeded()
        // Binding, not assumption: the view model resolves to the live window
        // manager while the pane is active.
        XCTAssertTrue(viewModel.boundWindowUndoManager === window.stubUndoManager)
        XCTAssertTrue(viewModel.workflowUndoManager === window.stubUndoManager)
        // First attach must retain the weak host (previous ordering cleared it).
        XCTAssertTrue(bridge.chainResponder.hostWindow === window)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
        // Single-stack proof: the registration went to the window manager the
        // native window drives — the owned fallback stays empty, so there is
        // no double registration and no competing stack.
        XCTAssertTrue(window.stubUndoManager.canUndo)
        XCTAssertEqual(window.stubUndoManager.undoActionName, "Change Workflow Status")
        XCTAssertFalse(owned.canUndo)

        // Native menu titles follow the window stack's action name (HIG).
        let undoItem = NSMenuItem(title: "Undo", action: #selector(StubUndoWindow.undo(_:)), keyEquivalent: "")
        XCTAssertTrue(window.validateMenuItem(undoItem))
        XCTAssertEqual(undoItem.title, window.stubUndoManager.undoMenuItemTitle)
        XCTAssertTrue(undoItem.title.contains("Change Workflow Status"))

        // The window's own action path — what AppKitWindow.undo: drives.
        window.undo(nil)
        XCTAssertNil(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus)
        XCTAssertTrue(window.stubUndoManager.canRedo)

        let redoItem = NSMenuItem(title: "Redo", action: #selector(StubUndoWindow.redo(_:)), keyEquivalent: "")
        XCTAssertTrue(window.validateMenuItem(redoItem))
        window.redo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)

        // Detach unbinds: later registrations fall back to the owned stack.
        bridge.removeFromSuperview()
        XCTAssertNil(viewModel.boundWindowUndoManager)
        XCTAssertTrue(viewModel.workflowUndoManager === owned)
        XCTAssertTrue(window.nextResponder !== bridge.chainResponder)
    }

    /// Inactive pane with a window-owned manager: no binding, so the workflow
    /// registration stays on the owned stack and the window's own `undo:`
    /// (empty manager) leaves the status untouched.
    func testInactiveBridgeUnbindsWindowManagerAndLeavesStatusUntouched() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = viewModel.ownedWorkflowUndoManager

        let window = StubUndoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: false)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()
        XCTAssertNil(viewModel.boundWindowUndoManager)
        XCTAssertTrue(viewModel.workflowUndoManager === owned)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(owned.canUndo)
        XCTAssertFalse(window.stubUndoManager.canUndo)
        XCTAssertNil(bridge.chainResponder.scopedUndoManager)

        window.undo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// A mounted-but-inactive bridge must not intercept the AppKit target:
    /// with a non-empty stack elsewhere, resolution skips us.
    func testInactiveBridgeDoesNotBecomeAppTarget() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = try XCTUnwrap(viewModel.workflowUndoManager)
        guard let app = NSApp else { XCTFail("NSApp is nil in test host"); return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: false)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()

        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(window.contentView)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(owned.canUndo)
        XCTAssertNil(bridge.chainResponder.scopedUndoManager)

        let undoSel = #selector(ArchiveWorkflowUndoChainResponder.undo(_:))
        XCTAssertFalse(bridge.chainResponder.responds(to: undoSel))
        let target = app.target(forAction: undoSel, to: nil, from: nil)
        XCTAssertTrue((target as AnyObject?) !== bridge.chainResponder)

        // Sending through AppKit must not drive the workflow stack.
        _ = app.sendAction(undoSel, to: nil, from: nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// A real text view before the bridge keeps its own undo: the bridge
    /// yields (no claim) and the AppKit target is not the bridge.
    func testTextEditingYieldsAppTargetToFieldEditor() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        _ = try XCTUnwrap(viewModel.workflowUndoManager)
        guard let app = NSApp else { XCTFail("NSApp is nil in test host"); return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: true)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        window.contentView?.addSubview(textView)

        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(textView)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(viewModel.workflowUndoManager?.canUndo == true) // plain NSWindow supplies its own manager, which the bridge binds
        // Bridge sees the real firstResponder (no override) and yields.
        bridge.chainResponder.isTextEditingOverride = nil
        XCTAssertNil(bridge.chainResponder.scopedUndoManager)

        let undoSel = #selector(ArchiveWorkflowUndoChainResponder.undo(_:))
        XCTAssertFalse(bridge.chainResponder.responds(to: undoSel))
        let target = app.target(forAction: undoSel, to: nil, from: nil)
        XCTAssertTrue((target as AnyObject?) !== bridge.chainResponder)
    }

    /// Reparent + intervening-responder safety: moving windows restores the
    /// old chain and preserves any responder spliced around the bridge.
    func testBridgeReparentAndInterveningDetachPreserveChain() throws {
        let windowA = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let windowB = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { windowA.orderOut(nil); windowB.orderOut(nil) }
        let originalA = windowA.nextResponder
        let originalB = windowB.nextResponder

        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: nil, isActive: true)
        windowA.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()
        XCTAssertTrue(windowA.nextResponder === bridge.chainResponder)
        XCTAssertTrue(bridge.chainResponder.hostWindow === windowA)

        // Reparent via remove/add (any window change detaches first).
        bridge.removeFromSuperview()
        if let originalA {
            XCTAssertTrue(windowA.nextResponder === originalA)
        } else {
            XCTAssertNil(windowA.nextResponder)
        }
        windowB.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()
        XCTAssertTrue(windowB.nextResponder === bridge.chainResponder)
        XCTAssertTrue(bridge.chainResponder.hostWindow === windowB)

        // Another responder splices between window and bridge; detach must
        // excise the bridge without severing the intervening link.
        let intervening = NSResponder()
        let downstream = bridge.chainResponder.nextResponder
        intervening.nextResponder = bridge.chainResponder
        windowB.nextResponder = intervening
        bridge.detach()
        XCTAssertTrue(windowB.nextResponder === intervening)
        if let downstream {
            XCTAssertTrue(intervening.nextResponder === downstream)
        } else {
            XCTAssertNil(intervening.nextResponder)
        }
        XCTAssertNil(bridge.chainResponder.nextResponder)
        XCTAssertNil(bridge.chainResponder.hostWindow)
        // The bridge captured window B's pre-attach downstream, so excising
        // it restores exactly that (no leak into window A).
        if let originalB {
            XCTAssertTrue(downstream === originalB)
        } else {
            XCTAssertNil(downstream)
        }
    }

    /// The registration proxy holds the view model weakly, so the retaining
    /// undo stack cannot pin the view model alive.
    func testUndoRegistrationTargetHoldsViewModelWeakly() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        XCTAssertTrue(viewModel.workflowUndoTarget.viewModel === viewModel)

        let probe = ArchiveWorkflowUndoTarget()
        probe.viewModel = viewModel
        XCTAssertTrue(probe.viewModel === viewModel)
        probe.viewModel = nil
        XCTAssertNil(probe.viewModel)
    }

    /// Deactivation scrubs this pane's registrations from the window manager:
    /// after `sync(isActive: false)` the window cannot undo and its `undo:`
    /// leaves the card status untouched (no invisible cross-tool revert).
    func testDeactivationViaSyncClearsWindowUndoActions() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = viewModel.ownedWorkflowUndoManager

        let window = StubUndoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: true)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()
        XCTAssertTrue(viewModel.boundWindowUndoManager === window.stubUndoManager)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
        XCTAssertTrue(window.stubUndoManager.canUndo)
        XCTAssertFalse(owned.canUndo)

        closeEventUndoGroup()
        bridge.sync(viewModel: viewModel, isActive: false)
        XCTAssertNil(viewModel.boundWindowUndoManager)
        XCTAssertFalse(window.undoManager!.canUndo)

        window.undo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// `detach()` (window removal path) scrubs this pane's registrations too.
    func testDetachClearsWindowUndoActions() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        let window = StubUndoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: true)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()
        XCTAssertTrue(viewModel.boundWindowUndoManager === window.stubUndoManager)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(window.stubUndoManager.canUndo)

        closeEventUndoGroup()
        bridge.detach()
        XCTAssertNil(viewModel.boundWindowUndoManager)
        XCTAssertFalse(window.undoManager!.canUndo)

        window.undo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// View-model swap: the previous view model's actions are removed from
    /// the window manager when the bridge moves to a second view model.
    func testViewModelSwapClearsPreviousWindowUndoActions() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let second = fixture.viewModel(runtime: runtime)

        let window = StubUndoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: true)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()
        XCTAssertTrue(viewModel.boundWindowUndoManager === window.stubUndoManager)

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(window.stubUndoManager.canUndo)

        closeEventUndoGroup()
        bridge.sync(viewModel: second, isActive: true)
        XCTAssertNil(viewModel.boundWindowUndoManager)
        XCTAssertTrue(second.boundWindowUndoManager === window.stubUndoManager)
        XCTAssertFalse(window.undoManager!.canUndo)

        window.undo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// Redo lands on the same window stack: `window.undo` pushes its inverse
    /// to the window manager (not the owned fallback) and `window.redo`
    /// restores the status.
    func testWindowUndoRedoStaysOnWindowStack() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })
        let owned = viewModel.ownedWorkflowUndoManager

        let window = StubUndoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: true)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(window.stubUndoManager.canUndo)

        window.undo(nil)
        XCTAssertNil(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus)
        XCTAssertTrue(window.undoManager!.canRedo)
        XCTAssertFalse(owned.canRedo)
        XCTAssertFalse(owned.canUndo)

        window.redo(nil)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// Scrubbing removes only the workflow target: an unrelated registration
    /// on the same window manager survives deactivation.
    func testNonWorkflowActionSurvivesDeactivation() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let viewModel = fixture.viewModel(runtime: try fixture.runtime())
        await viewModel.scan()
        let song = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == fixture.project.lastPathComponent })

        let window = StubUndoWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let bridge = ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: true)
        window.contentView?.addSubview(bridge)
        bridge.attachIfNeeded()

        viewModel.applyWorkflowStatus(.prod, for: song)
        XCTAssertTrue(window.stubUndoManager.canUndo)

        let other = OtherWorkflowUndoTarget()
        window.stubUndoManager.registerUndo(withTarget: other) { target in
            target.didUndo = true
        }

        closeEventUndoGroup()
        bridge.sync(viewModel: viewModel, isActive: false)
        XCTAssertNil(viewModel.boundWindowUndoManager)
        // The foreign action survives the workflow scrub.
        XCTAssertTrue(window.undoManager!.canUndo)

        window.undo(nil)
        XCTAssertTrue(other.didUndo)
        XCTAssertEqual(viewModel.songs.first(where: { $0.id == song.id })?.workflowStatus, .prod)
    }

    /// UndoManager (groupsByEvent) keeps a registration in an open group until
    /// the run loop cycles; `removeAllActions(withTarget:)` ignores open groups.
    /// Live, a tool switch is always a later event, so close the group here the
    /// way the next event would.
    private func closeEventUndoGroup() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for workflow undo state")
    }
}

private final class StubArchiveUndoWindowDelegate: NSObject, NSWindowDelegate {}

/// Foreign undo target: proves deactivation scrubbing removes only the
/// workflow target and leaves unrelated window-manager actions intact.
private final class OtherWorkflowUndoTarget: NSObject {
    var didUndo = false
}

/// Mimics SwiftUI's private `AppKitWindow` undo behavior with a real
/// `NSWindow.undoManager`: the window answers `undo:`/`redo:` itself from
/// its own manager and validates menu items against it. Lets headless tests
/// exercise the window-manager binding end behavior without relying on
/// `NSApp.target(forAction:)` key-window resolution (nil headless) or on the
/// bridge classname (live, the target legitimately stays the window).
private final class StubUndoWindow: NSWindow {
    let stubUndoManager = UndoManager()

    override var undoManager: UndoManager? { stubUndoManager }

    @objc func undo(_ sender: Any?) {
        stubUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        stubUndoManager.redo()
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(StubUndoWindow.undo(_:)) {
            guard stubUndoManager.canUndo else { return false }
            menuItem.title = stubUndoManager.undoMenuItemTitle
            return true
        }
        if menuItem.action == #selector(StubUndoWindow.redo(_:)) {
            guard stubUndoManager.canRedo else { return false }
            menuItem.title = stubUndoManager.redoMenuItemTitle
            return true
        }
        return super.validateMenuItem(menuItem)
    }
}
