import Combine
import Foundation
import SwiftUI

/// Observable routing store for quick-access menu commands.
///
/// Phase 47 (MenuBarExtra) sends commands here; `AppShellView` observes
/// `selectedToolID` and `revealOutputInbox` via `.onChange` to drive its
/// existing `@State` (ROUT-07). The router never constructs tool views
/// directly and never touches the output-inbox allowlist layer (HAND-04).
@MainActor
public final class QuickAccessRouter: ObservableObject {
    /// The tool the shell should select. `nil` means no pending selection.
    @Published public private(set) var selectedToolID: ToolFeatureID?

    /// When `true`, `AppShellView` should make the Output Inbox panel visible
    /// and then call `clearRevealOutputInbox()` to reset this flag.
    @Published public private(set) var revealOutputInbox: Bool = false

    /// Audio files to prefill in the WAV converter after `openConverter(with:)`.
    @Published public private(set) var prefilledConverterURLs: [URL] = []

    /// Monotonic request counter so repeated Find (⌘F / ⌥⌘F) and Search Archive… commands are observable.
    @Published public private(set) var archiveSearchFocusRequest: UInt64 = 0

    /// Pending Settings pane. Does not change `selectedToolID`.
    @Published public private(set) var openSettingsPane: HubSettingsPane?

    public init() {}

    /// Process a quick-access command.
    public func execute(_ command: QuickAccessCommand) {
        switch command {
        case .openTool(let id):
            // Tools menu (NMH-013) and MenuBarExtra both select content tools here.
            selectedToolID = id
        case .openApp, .quitApp:
            // Window activate / terminate live in the menu and Dock targets.
            // Do not change `selectedToolID`.
            break
        case .revealOutputInbox:
            revealOutputInbox = true
        case .focusArchiveSearch:
            selectedToolID = ToolFeatureID("archive-browser")
            archiveSearchFocusRequest &+= 1
        }
    }

    public func consumeArchiveSearchFocusRequest() {
        NotificationCenter.default.post(name: .archiveSearchFocusRequested, object: nil)
    }

    /// Reset the Output Inbox reveal trigger.
    /// `AppShellView` calls this after reading `revealOutputInbox = true`
    /// to prevent the flag from remaining stuck (per RESEARCH.md pitfall 3).
    public func clearRevealOutputInbox() {
        revealOutputInbox = false
    }

    /// Reset the selected tool ID to `nil` after it has been consumed by the view.
    /// `AppShellView` calls this inside `.onChange(of: router.selectedToolID)` so
    /// that a repeated `openTool` command for the same ID transitions
    /// `selectedToolID` from the ID → `nil` → the ID again, ensuring `.onChange`
    /// fires on every command even when consecutive commands name the same tool.
    public func clearSelectedToolID() {
        selectedToolID = nil
    }

    public func openConverter(with urls: [URL]) {
        prefilledConverterURLs = urls
        selectedToolID = ToolFeatureID("wav-converter")
    }

    public func consumePrefilledConverterURLs() -> [URL] {
        let urls = prefilledConverterURLs
        prefilledConverterURLs = []
        return urls
    }

    /// Open a Settings pane without selecting the Settings sidebar tool.
    public func requestSettingsPane(_ pane: HubSettingsPane) {
        openSettingsPane = pane
        NotificationCenter.default.post(name: .hubOpenSettingsPane, object: pane)
    }

    /// Open in-app Settings → Helpers (helper-missing recovery, NMH-010).
    public func openSettingsHelpers() {
        requestSettingsPane(.helpers)
    }

    public func clearOpenSettingsPane() {
        openSettingsPane = nil
    }
}

public extension Notification.Name {
    static let archiveSearchFocusRequested = Notification.Name("NikoMusicHub.archiveSearchFocusRequested")
    /// Opens Archive Browser New Song Draft sheet (NMH-138 Accept / Song menu).
    static let archiveNewSongDraftRequested = Notification.Name("NikoMusicHub.archiveNewSongDraftRequested")
}
