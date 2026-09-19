import Foundation

public protocol OutputInboxStore: Sendable {
    func listItems() throws -> [OutputInboxItem]
    func addItem(_ item: OutputInboxItem) throws
    func updateItem(_ item: OutputInboxItem) throws
    func refreshAvailability() throws
    /// Single-pass refresh + sorted snapshot.
    ///
    /// Blocking filesystem/JSON I/O: call off the main actor (see
    /// `OutputInboxRefreshModel`). The default implementation preserves the
    /// historical two-step behavior (`refreshAvailability()` + `listItems()`);
    /// stores may override it with one load/sort pass. Ordering, dedup,
    /// error (corrupt JSON throws) and "no history cap" semantics must match
    /// `listItems()`.
    func loadRefreshedItems() throws -> [OutputInboxItem]
}

public extension OutputInboxStore {
    func loadRefreshedItems() throws -> [OutputInboxItem] {
        try refreshAvailability()
        return try listItems()
    }
}
