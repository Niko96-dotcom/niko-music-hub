import Combine
import Foundation

/// One tool's newest Output Inbox rows, for the list on the tool's page.
///
/// Read side only. A pass calls `listItems()` off the main actor and never
/// writes, refreshes availability or drains the corruption warning; the
/// Output Inbox panel owns those (`OutputInboxRefreshModel`).
///
/// - Follows `.outputInboxDidChange` from `init` until the model is released.
/// - Requests coalesce as in `OutputInboxRefreshModel`: a request during a
///   pass forces exactly one follow-up pass, so no request is lost and a burst
///   never queues more.
/// - `items` is assigned only when the tool's slice changed, so an inbox
///   change for another tool does not re-render this tool's page.
/// - A failed pass keeps the current items. The Output Inbox panel reads the
///   same file and shows read errors.
@MainActor
public final class ToolRecentOutputs: ObservableObject {
    /// The tool's rows, newest first (`createdAt`), at most `limit`.
    @Published public private(set) var items: [OutputInboxItem] = []

    private let store: any OutputInboxStore
    private let toolID: ToolFeatureID
    private let limit: Int?
    private var inboxChanges: AnyCancellable?
    private var passTask: Task<Void, Never>?
    private var needsAnotherPass = false

    /// Reads nothing until the first inbox change or `refresh()`.
    /// `limit: nil` keeps every row of the tool.
    public init(store: any OutputInboxStore, toolID: ToolFeatureID, limit: Int? = nil) {
        self.store = store
        self.toolID = toolID
        self.limit = limit
        // The store posts on the main thread; the hop keeps the main actor
        // safe for any other poster.
        inboxChanges = NotificationCenter.default.publisher(for: .outputInboxDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Starts a pass and returns at once.
    public func refresh() {
        if passTask != nil {
            needsAnotherPass = true
            return
        }
        passTask = Task { [weak self] in
            await self?.runPasses()
        }
    }

    /// Returns when no pass runs and none is pending. For tests.
    public func waitForIdle() async {
        while let task = passTask {
            await task.value
        }
    }

    private func runPasses() async {
        repeat {
            needsAnotherPass = false
            if let slice = await readSlice(), slice != items {
                items = slice
            }
        } while needsAnotherPass && !Task.isCancelled
        passTask = nil
    }

    /// The tool's slice, read, filtered and sorted off the main actor; nil when
    /// the store throws.
    private func readSlice() async -> [OutputInboxItem]? {
        let store = store
        let toolID = toolID
        let limit = limit
        return await Task.detached(priority: .utility) { () -> [OutputInboxItem]? in
            guard let all = try? store.listItems() else { return nil }
            let rows = all
                .filter { $0.sourceToolID == toolID }
                .sorted { $0.createdAt > $1.createdAt }
            return limit.map { Array(rows.prefix($0)) } ?? rows
        }.value
    }
}
