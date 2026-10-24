import SwiftUI

/// The shell's Esc on one tool pane: what Edit ▸ Cancel cancels while that pane is shown
/// (`InAppJobCancelRouting.escapeJobs`). `HubCancelCommands` and `HubInspectorPage` both act
/// through it, so the menu item and the key cancel the same jobs.
///
/// AppKit offers a key without ⌘ to the main menu only while no window is key. In the main
/// window a plain Esc goes to the window (`keyDown:`, then `cancelOperation:`), which looks
/// only for its own cancel button, so the menu item's Esc never fires there (traced live,
/// 2026-10-24). `HubInspectorPage` therefore binds this Esc in the window while the visible
/// page has no enabled cancel key; the menu item shows the key and answers a click.
public struct HubShellEscape: Equatable, Sendable {
    public let jobStatusCenter: ShellJobStatusCenter
    public let tool: ToolMetadata?

    public init(jobStatusCenter: ShellJobStatusCenter, tool: ToolMetadata?) {
        self.jobStatusCenter = jobStatusCenter
        self.tool = tool
    }

    /// Empty while nothing runs that Esc cancels on this pane.
    public var jobs: [ShellJobStatus] {
        InAppJobCancelRouting.escapeJobs(selectedTool: tool, in: jobStatusCenter.jobs)
    }

    public func cancel() {
        jobStatusCenter.cancel(jobs)
    }

    public static func == (lhs: HubShellEscape, rhs: HubShellEscape) -> Bool {
        lhs.jobStatusCenter === rhs.jobStatusCenter && lhs.tool == rhs.tool
    }
}

private struct HubShellEscapeKey: EnvironmentKey {
    static let defaultValue: HubShellEscape? = nil
}

public extension EnvironmentValues {
    /// Set by the shell on each tool pane it mounts; nil outside the shell (previews, tests).
    var hubShellEscape: HubShellEscape? {
        get { self[HubShellEscapeKey.self] }
        set { self[HubShellEscapeKey.self] = newValue }
    }
}
