import Foundation

/// What Esc and ⌘. cancel as one group (NMH-009). The job's tool supplies it
/// (`ShellJobStatus.cancelTarget`). The case order is the ⌘. order: the first
/// target that has a running job wins.
public enum InAppJobCancelTarget: Comparable, Codable, Sendable {
    case download
    case stemSeparation
    case conversion
    case vaultTransfer
    case scan
}

/// Which in-app jobs Esc and ⌘. cancel (NMH-009). Pure routing over the
/// `ShellJobStatusCenter` job list: each job says what it is (`cancelTarget`,
/// `sourceToolID`) and each tool whether its pane keeps Esc
/// (`ToolMetadata.handlesEscape`), so the routing knows no tool. The menu
/// commands live in `HubCancelCommands`.
public enum InAppJobCancelRouting {
    /// Esc. A pane that handles Esc cancels its own tool's jobs and nothing else
    /// (the archive keeps Esc for its own views: it owns no job with a target).
    /// Any other pane, or none, cancels the shell work (jobs of no tool, such as
    /// a Vault transfer or a scan) of the first target present.
    public static func escapeJobs(selectedTool: ToolMetadata?, in jobs: [ShellJobStatus]) -> [ShellJobStatus] {
        let cancellable = jobs.filter { $0.cancelTarget != nil }
        if let selectedTool, selectedTool.handlesEscape {
            return cancellable.filter { $0.sourceToolID == selectedTool.id }
        }
        return firstTargetJobs(in: cancellable.filter { $0.sourceToolID == nil })
    }

    /// ⌘.: every job of the first target present, whatever pane is selected.
    public static func commandPeriodJobs(in jobs: [ShellJobStatus]) -> [ShellJobStatus] {
        firstTargetJobs(in: jobs)
    }

    private static func firstTargetJobs(in jobs: [ShellJobStatus]) -> [ShellJobStatus] {
        guard let first = jobs.compactMap(\.cancelTarget).min() else { return [] }
        return jobs.filter { $0.cancelTarget == first }
    }
}
