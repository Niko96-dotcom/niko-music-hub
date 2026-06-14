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

    public init() {}

    /// Process a quick-access command.
    public func execute(_ command: QuickAccessCommand) {
        switch command {
        case .openTool(let id):
            selectedToolID = id
        case .openApp:
            // No-op at the model layer in Phase 46.
            // Phase 47 will call NSApp.activate when consuming this command.
            break
        case .revealOutputInbox:
            revealOutputInbox = true
        }
    }

    /// Reset the Output Inbox reveal trigger.
    /// `AppShellView` calls this after reading `revealOutputInbox = true`
    /// to prevent the flag from remaining stuck (per RESEARCH.md pitfall 3).
    public func clearRevealOutputInbox() {
        revealOutputInbox = false
    }
}
