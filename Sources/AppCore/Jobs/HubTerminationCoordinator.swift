import Foundation

/// The quit alert for running work (ADR-019). The app delegate shows it as an
/// `NSAlert`; the keep-open button comes first so Return keeps the work.
public struct HubQuitPrompt: Equatable, Sendable {
    public let work: [ShellJobStatus]

    public init(work: [ShellJobStatus]) {
        self.work = work
    }

    public var title: String {
        work.count == 1 ? "1 job is still running" : "\(work.count) jobs are still running"
    }

    public var message: String {
        var lines = work.map(\.displayLine)
        lines.append("")
        if work.contains(where: { $0.id == ShellJobExtraSourceID.vaultTransfer }) {
            lines.append(
                "Quitting stops them. Project Vault cancels its waiting requests and stops the transfer at the next safe point; existing recovery records are kept."
            )
        } else {
            lines.append("Quitting stops them.")
        }
        return lines.joined(separator: "\n")
    }

    public var keepOpenButton: String { "Keep Music Hub Open" }
    public var quitButton: String { "Stop and Quit" }
}

/// Decides what quit does with the work registered in `ShellJobStatusCenter`
/// (ADR-019). Nothing registered: quit now. Otherwise ask; on confirm cancel
/// everything and reply once the work has unwound or the deadline passes, so
/// a cancel that never finishes (a hung recorder stop, ENG-14) cannot block
/// quit. The delegate returns `.terminateLater` meanwhile, which keeps the run
/// loop and main-actor cancels running.
@MainActor
public final class HubTerminationCoordinator {
    public enum Decision: Equatable, Sendable {
        case terminateNow
        case ask(HubQuitPrompt)
        /// Nothing left to ask about, but work cancelled earlier (from the jobs
        /// strip) is still unwinding: wait for it without asking.
        case waitForCancelledWork
    }

    /// Long enough for helper teardown and partial-file cleanup; after it,
    /// `applicationWillTerminate` still reaps any live helper process group.
    public static let defaultDeadline: Duration = .seconds(5)

    private let center: ShellJobStatusCenter
    private let deadline: Duration
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private var waitTask: Task<Void, Never>?

    public init(
        jobStatusCenter: ShellJobStatusCenter,
        deadline: Duration = HubTerminationCoordinator.defaultDeadline,
        pollInterval: Duration = .milliseconds(50),
        sleep: (@Sendable (Duration) async -> Void)? = nil
    ) {
        center = jobStatusCenter
        self.deadline = deadline
        self.pollInterval = pollInterval
        // The default lives here, not in the signature: an async closure as a
        // default argument is emitted into every calling module, and two such
        // copies in one test binary crashed the task allocator ("freed pointer
        // was not the last allocation").
        self.sleep = sleep ?? { try? await Task.sleep(for: $0) }
    }

    /// True once quit is confirmed; a repeated quit request then waits for the
    /// pending reply instead of asking again.
    public var isStoppingWork: Bool { waitTask != nil }

    /// The delegate's answer without AppKit (ADR-019).
    public enum TerminateAnswer: Equatable, Sendable { case now, cancel, later }

    /// The delegate's whole applicationShouldTerminate decision (ADR-019), without AppKit.
    public func answerTerminateRequest(
        confirm: (HubQuitPrompt) -> Bool,
        reply: @escaping @MainActor () -> Void
    ) -> TerminateAnswer {
        if isStoppingWork { return .later }
        switch decision() {
        case .terminateNow:
            return .now
        case .waitForCancelledWork:
            break
        case .ask(let prompt):
            guard confirm(prompt) else { return .cancel }
        }
        cancelRunningWork(thenReply: reply)
        return .later
    }

    public func decision() -> Decision {
        let work = center.quitBlockingWork
        if !work.isEmpty { return .ask(HubQuitPrompt(work: work)) }
        return center.hasUnfinishedQuitBlockingWork ? .waitForCancelledWork : .terminateNow
    }

    /// Confirmed quit, or `.waitForCancelledWork`. Replies exactly once; a
    /// second call while waiting is ignored.
    public func cancelRunningWork(thenReply reply: @escaping @MainActor () -> Void) {
        guard waitTask == nil else { return }
        center.cancelAllForQuit()
        let center = center
        let deadline = deadline
        let pollInterval = pollInterval
        let sleep = sleep
        waitTask = Task { @MainActor in
            // Elapsed time is counted in polls so tests can inject the clock.
            var waited: Duration = .zero
            while center.hasUnfinishedQuitBlockingWork, waited < deadline {
                await sleep(pollInterval)
                waited += pollInterval
            }
            reply()
        }
    }
}
