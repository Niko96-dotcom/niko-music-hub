import AppKit
import Foundation
import NikoMusicCore
import SwiftUI

/// Weak proxy that breaks the viewModel → UndoManager → target → viewModel
/// retain cycle.
///
/// `UndoManager.registerUndo(withTarget:)` retains its target until the stack
/// is cleared. Registering with the view model itself would therefore pin the
/// view model forever. The view model owns both the stack and this target; the
/// stack retains only the target, which points back weakly.
@MainActor
final class ArchiveWorkflowUndoTarget: NSObject {
    weak var viewModel: ArchiveBrowserViewModel?

    func undoWorkflowStatus(
        songID: String,
        previousStatus: ProjectWorkflowStatus?,
        actionName: String
    ) {
        viewModel?.undoWorkflowStatus(
            songID: songID,
            previousStatus: previousStatus,
            actionName: actionName
        )
    }

    func undoMetadata(
        songID: String,
        previousVirtualTitle: String?,
        previousAliases: [String],
        previousAppNote: String?,
        actionName: String
    ) {
        viewModel?.undoMetadata(
            songID: songID,
            previousVirtualTitle: previousVirtualTitle,
            previousAliases: previousAliases,
            previousAppNote: previousAppNote,
            actionName: actionName
        )
    }
}

/// Native Edit-menu hook for the non-document main window.
///
/// SwiftUI's key window (`AppKitWindow`) answers `undo:` itself, ahead of any
/// responder spliced into `window.nextResponder`. The primary route is
/// therefore binding: the bridge view publishes the window's existing
/// `undoManager` to `viewModel.boundWindowUndoManager` while this pane is
/// active, so workflow registrations land on the manager the window's own
/// `undo:` drives. This responder is the fallback for windows without a
/// manager: it sits after the field editor, hosting views, and the window,
/// never touches the window delegate, and its `responds(to:)` gating keeps an
/// inactive, text-editing, or empty-stack bridge from claiming the action.
/// `EnvironmentValues.undoManager` is get-only, so it cannot be wired instead.
@MainActor
final class ArchiveWorkflowUndoChainResponder: NSResponder, NSMenuItemValidation, NSUserInterfaceValidations {
    weak var viewModel: ArchiveBrowserViewModel?
    var isActive = false
    weak var hostWindow: NSWindow?
    /// Test seam: nil means "ask the hosted/key window".
    var isTextEditingOverride: Bool?

    var scopedUndoManager: UndoManager? {
        guard isActive, let viewModel else { return nil }
        guard !isTextEditing else { return nil }
        return viewModel.workflowUndoManager
    }

    private var isTextEditing: Bool {
        if let override = isTextEditingOverride { return override }
        let first = hostWindow?.firstResponder ?? NSApp?.keyWindow?.firstResponder
        return ArchiveShortcutFocusPolicy.isTextEditing(first)
    }

    override var undoManager: UndoManager? { scopedUndoManager }

    /// Gate AppKit target resolution: only claim `undo:`/`redo:` when this
    /// bridge can actually perform them. Otherwise return false so AppKit
    /// continues down the chain (field editor, NSApp, app delegate) instead
    /// of locking onto us and disabling the menu.
    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(ArchiveWorkflowUndoChainResponder.undo(_:)) {
            return scopedUndoManager?.canUndo == true
        }
        if aSelector == #selector(ArchiveWorkflowUndoChainResponder.redo(_:)) {
            return scopedUndoManager?.canRedo == true
        }
        return super.responds(to: aSelector)
    }

    @objc func undo(_ sender: Any?) {
        scopedUndoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        scopedUndoManager?.redo()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(ArchiveWorkflowUndoChainResponder.undo(_:)) {
            guard let manager = scopedUndoManager, manager.canUndo else { return false }
            menuItem.title = manager.undoMenuItemTitle
            return true
        }
        if menuItem.action == #selector(ArchiveWorkflowUndoChainResponder.redo(_:)) {
            guard let manager = scopedUndoManager, manager.canRedo else { return false }
            menuItem.title = manager.redoMenuItemTitle
            return true
        }
        return false
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(ArchiveWorkflowUndoChainResponder.undo(_:)) {
            guard let manager = scopedUndoManager, manager.canUndo else { return false }
            (item as? NSMenuItem)?.title = manager.undoMenuItemTitle
            return true
        }
        if item.action == #selector(ArchiveWorkflowUndoChainResponder.redo(_:)) {
            guard let manager = scopedUndoManager, manager.canRedo else { return false }
            (item as? NSMenuItem)?.title = manager.redoMenuItemTitle
            return true
        }
        return false
    }
}

/// Zero-size lifecycle host. Follows the `ArchiveBoardDropHostingView`
/// `viewWillMove(toWindow:)` pattern: splice into `window.nextResponder` on
/// arrival, restore the previous chain on removal or reparent. The window
/// delegate is never touched; no polling, no process-wide monitors, no focus
/// theft. No `deinit` detach: the class is `@MainActor` (nonisolated deinit
/// cannot call isolated `detach()`), and AppKit always routes removal
/// through `viewWillMove(toWindow: nil)` first; window dealloc tears down
/// the chain with it.
@MainActor
final class ArchiveWorkflowUndoBridgeView: NSView {
    weak var viewModel: ArchiveBrowserViewModel?
    var isActive = false
    let chainResponder = ArchiveWorkflowUndoChainResponder()
    private weak var attachedWindow: NSWindow?
    private weak var savedNextResponder: NSResponder?

    init(viewModel: ArchiveBrowserViewModel?, isActive: Bool) {
        self.viewModel = viewModel
        self.isActive = isActive
        super.init(frame: .zero)
        chainResponder.viewModel = viewModel
        chainResponder.isActive = isActive
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Detach on ANY window change (removal or reparent), not just nil: a
        // reparent that skips teardown would leave this responder spliced into
        // the old window while `attachedWindow` points at the new one.
        if newWindow !== window { detach() }
        super.viewWillMove(toWindow: newWindow)
    }

    func sync(viewModel: ArchiveBrowserViewModel?, isActive: Bool) {
        if self.viewModel !== viewModel {
            // Never leave a stale binding on a view model we no longer serve.
            // Scrub its registrations from the old window manager first so a
            // later window undo cannot revert this pane while another tool
            // shows (the shell keeps panes mounted and only flips isActive).
            clearBoundWindowUndoManager(for: self.viewModel)
        }
        self.viewModel = viewModel
        self.isActive = isActive
        chainResponder.viewModel = viewModel
        chainResponder.isActive = isActive
        bindWindowUndoManager()
    }

    func attachIfNeeded() {
        guard let window else {
            detachFromStaleWindow()
            return
        }
        // Already spliced into this window: refresh the weak host + flags.
        // (Assign hostWindow AFTER the identity check so the first attach is
        // not cleared by detach() below — the previous ordering assigned
        // before detach and the first attach ended with hostWindow == nil.)
        if attachedWindow === window {
            chainResponder.hostWindow = window
        } else {
            // detach() clears the window-manager binding too, so it must run
            // BEFORE re-binding below.
            detach()
            chainResponder.hostWindow = window
            savedNextResponder = window.nextResponder
            chainResponder.nextResponder = savedNextResponder
            window.nextResponder = chainResponder
            attachedWindow = window
        }
        bindWindowUndoManager()
    }

    func detach() {
        exciseChainResponder()
        chainResponder.hostWindow = nil
        attachedWindow = nil
        savedNextResponder = nil
        // Unbind: registrations after this resolve to the owned stack again.
        // Scrub this view model's actions from the window-owned manager first
        // so a later window undo cannot revert this pane (or cancel a Project
        // Vault transfer) while another tool shows. Only our target is
        // removed; other targets (e.g. text editing) are left intact.
        clearBoundWindowUndoManager(for: viewModel)
    }

    /// Primary native route: publish the window's EXISTING undo manager (when
    /// the window provides one) as the registration target while this pane is
    /// active. Inactive or windowless → nil → the owned stack. Never creates
    /// a manager, never touches the delegate, never forces focus.
    private func bindWindowUndoManager() {
        guard let viewModel else { return }
        if isActive, let windowManager = window?.undoManager {
            if viewModel.boundWindowUndoManager !== windowManager {
                // Replacing the binding (nil or a different window): scrub the
                // old manager first so stale actions cannot fire cross-tool.
                clearBoundWindowUndoManager(for: viewModel)
                viewModel.boundWindowUndoManager = windowManager
            }
        } else {
            clearBoundWindowUndoManager(for: viewModel)
        }
    }

    /// Remove `chainResponder` wherever it sits downstream of the attached
    /// window, preserving surrounding links. The previous
    /// `attachedWindow.nextResponder === chainResponder` check severed the
    /// chain when another responder had spliced in between or downstream.
    private func exciseChainResponder() {
        guard let attachedWindow else {
            chainResponder.nextResponder = nil
            return
        }
        // Bounded walk: responder chains are short; cap to avoid any cycle.
        var predecessor: NSResponder? = attachedWindow
        for _ in 0..<64 {
            guard let next = predecessor?.nextResponder else { break }
            if next === chainResponder {
                predecessor?.nextResponder = chainResponder.nextResponder
                break
            }
            predecessor = next
        }
        chainResponder.nextResponder = nil
    }

    private func detachFromStaleWindow() {
        if attachedWindow != nil { detach() }
        chainResponder.hostWindow = nil
        clearBoundWindowUndoManager(for: viewModel)
    }

    /// Scrub only this view model's registrations from the previously bound
    /// window manager, leaving other targets (e.g. text editing) intact.
    /// Must run before clearing or replacing the binding.
    private func clearBoundWindowUndoManager(for viewModel: ArchiveBrowserViewModel?) {
        guard let viewModel, let oldManager = viewModel.boundWindowUndoManager else {
            viewModel?.boundWindowUndoManager = nil
            return
        }
        oldManager.removeAllActions(withTarget: viewModel.workflowUndoTarget)
        viewModel.boundWindowUndoManager = nil
    }
}

/// SwiftUI entry point. Applied as a `.background` so it never affects layout,
/// focus, or the design-contract keylines.
struct ArchiveWorkflowUndoBridge: NSViewRepresentable {
    let viewModel: ArchiveBrowserViewModel
    let isActive: Bool

    func makeNSView(context: Context) -> ArchiveWorkflowUndoBridgeView {
        ArchiveWorkflowUndoBridgeView(viewModel: viewModel, isActive: isActive)
    }

    func updateNSView(_ nsView: ArchiveWorkflowUndoBridgeView, context: Context) {
        nsView.sync(viewModel: viewModel, isActive: isActive)
        nsView.attachIfNeeded()
    }
}
