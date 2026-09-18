import Combine
import Foundation
import SwiftUI

/// One tool-open request. `sequence` is monotonic so two consecutive requests
/// for the same tool are still distinct values for `onChange`.
public struct QuickAccessToolRequest: Equatable, Sendable {
    public let sequence: UInt64
    public let toolID: ToolFeatureID
}

/// Observable routing store for quick-access menu commands.
///
/// Phase 47 (MenuBarExtra) sends commands here; `AppShellView` observes the
/// pending requests via `.onChange` and applies them to the shell session,
/// which owns the selected tool (ROUT-07). The router never constructs tool
/// views directly and never touches the output-inbox allowlist layer (HAND-04).
///
/// Requests are one-shot values with a sequence number, not "pending state the
/// consumer must clear": repeating the same request produces a new value.
@MainActor
public final class QuickAccessRouter: ObservableObject {
    /// The most recent tool-open request. The shell reacts to changes; there is
    /// nothing to clear.
    @Published public private(set) var toolRequest: QuickAccessToolRequest?

    /// When `true`, `AppShellView` should make the Output Inbox panel visible
    /// and then call `clearRevealOutputInbox()` to reset this flag.
    @Published public private(set) var revealOutputInbox: Bool = false

    /// Audio files to prefill in the WAV converter after `openConverter(with:)`.
    @Published public private(set) var prefilledConverterURLs: [URL] = []

    /// Monotonic request counter so repeated Find (⌘F / ⌥⌘F) and Search Archive… commands are observable.
    @Published public private(set) var archiveSearchFocusRequest: UInt64 = 0

    /// Pending Settings pane. Does not request a tool. `HubSettingsRoot` consumes
    /// it (`clearOpenSettingsPane()`); the shell opens the Settings window on change.
    @Published public private(set) var openSettingsPane: HubSettingsPane?

    private var toolRequestSequence: UInt64 = 0

    /// Nonisolated so `ToolContext` (a plain `Sendable` value) can default it.
    nonisolated public init() {}

    /// Tool named by the latest request, if any.
    public var requestedToolID: ToolFeatureID? { toolRequest?.toolID }

    /// Process a quick-access command.
    public func execute(_ command: QuickAccessCommand) {
        switch command {
        case .openTool(let id):
            // Tools menu (NMH-013) and MenuBarExtra both select content tools here.
            requestTool(id)
        case .openApp, .quitApp:
            // Window activate / terminate live in the menu and Dock targets.
            // Do not request a tool.
            break
        case .revealOutputInbox:
            revealOutputInbox = true
        case .focusArchiveSearch:
            requestTool(ToolFeatureID("archive-browser"))
            archiveSearchFocusRequest &+= 1
        }
    }

    private func requestTool(_ id: ToolFeatureID) {
        toolRequestSequence &+= 1
        toolRequest = QuickAccessToolRequest(sequence: toolRequestSequence, toolID: id)
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

    public func openConverter(with urls: [URL]) {
        prefilledConverterURLs = urls
        requestTool(ToolFeatureID("wav-converter"))
    }

    public func consumePrefilledConverterURLs() -> [URL] {
        let urls = prefilledConverterURLs
        prefilledConverterURLs = []
        return urls
    }

    /// Open a Settings pane without requesting a tool. The single path for
    /// every "open Settings → pane" deep link (feature views reach it through
    /// `ToolContext.router`).
    public func requestSettingsPane(_ pane: HubSettingsPane) {
        openSettingsPane = pane
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
