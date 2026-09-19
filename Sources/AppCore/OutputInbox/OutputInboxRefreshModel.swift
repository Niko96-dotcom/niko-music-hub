import Combine
import Foundation

/// Main-actor owned refresh state for the Output Inbox.
///
/// Smallest clear boundary for the refresh fix: the view (and any future
/// caller) asks for a refresh without touching the filesystem, and this model
/// runs the blocking `loadRefreshedItems()` pass on a background task, then
/// publishes the latest snapshot.
///
/// - All filesystem/JSON I/O runs off the main actor (`Task.detached` with
///   `.utility` priority). `requestRefresh()` itself never blocks.
/// - Notification bursts coalesce: a request arriving while a pass is
///   in-flight sets a flag that forces exactly one follow-up pass, so no
///   requested refresh is lost but N bursts never cause N passes.
/// - Total work is unchanged (one load/scan/save/sort per pass); the win is
///   main-thread responsiveness, not less work. Do not claim otherwise.
/// - Corruption is surfaced via `lastError`, never masked: a failed pass
///   keeps the previous `items` and records the failure message; the next
///   request retries from disk, so recovery needs no restart.
@MainActor
public final class OutputInboxRefreshModel: ObservableObject {
    @Published public private(set) var items: [OutputInboxItem] = []
    @Published public private(set) var lastError: String?
    @Published public private(set) var isRefreshing = false

    private let store: any OutputInboxStore
    private var refreshTask: Task<Void, Never>?
    private var needsAnotherPass = false

    public init(store: any OutputInboxStore) {
        self.store = store
    }

    /// Request a refresh. Returns immediately; safe to call from notification
    /// handlers that may fire in bursts.
    public func requestRefresh() {
        if refreshTask != nil {
            needsAnotherPass = true
            return
        }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }

    /// Test/coordinator seam: returns when no pass is in-flight and no
    /// follow-up is pending.
    public func waitForIdle() async {
        while true {
            guard let task = refreshTask else { return }
            await task.value
        }
    }

    public func cancel() {
        refreshTask?.cancel()
    }

    private func runRefreshLoop() async {
        repeat {
            needsAnotherPass = false
            let outcome = await runOnePass()
            guard !Task.isCancelled else { break }
            switch outcome {
            case .success(let snapshot):
                items = snapshot
                lastError = nil
            case .failure(let message):
                lastError = message
            }
        } while needsAnotherPass && !Task.isCancelled
        refreshTask = nil
        isRefreshing = false
    }

    /// Runs the blocking store call off the main actor. Only `Sendable`
    /// values (snapshot array, error message string) cross the boundary.
    private enum RefreshOutcome: Sendable {
        case success([OutputInboxItem])
        case failure(String)
    }

    private func runOnePass() async -> RefreshOutcome {
        let store = self.store
        return await Task.detached(priority: .utility) { () -> RefreshOutcome in
            do {
                return .success(try store.loadRefreshedItems())
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }
}
