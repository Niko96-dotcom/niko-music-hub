import Foundation

public protocol OutputInboxStore: Sendable {
    func listItems() throws -> [OutputInboxItem]
    func addItem(_ item: OutputInboxItem) throws
    func updateItem(_ item: OutputInboxItem) throws
    /// Atomically patches BPM metadata keys for one row.
    ///
    /// The caller supplies only BPM keys (for example `"bpm"` and
    /// `"bpmConfidence"`); the store merges exactly those entries into the
    /// current row, preserving every newer unrelated field. The store reloads
    /// the row under its own lock and skips (returning `false`, without
    /// resurrecting or modifying anything) when the id is missing, the row is
    /// not `.available`, the stored file URL differs from `expectedFileURL`,
    /// or the file itself is currently gone. Callers must pass the file URL
    /// captured before the async estimate; never a re-read UI snapshot.
    /// - Returns: `true` when the keys were merged and saved, `false` when
    ///   skipped as stale. Real I/O failures still throw.
    func patchBPMMetadata(id: UUID, expectedFileURL: URL, bpmMetadata: [String: String]) throws -> Bool
    func refreshAvailability() throws
    /// Single-pass refresh + sorted snapshot.
    ///
    /// Blocking filesystem/JSON I/O: call off the main actor (see
    /// `OutputInboxRefreshModel`). The default implementation preserves the
    /// historical two-step behavior (`refreshAvailability()` + `listItems()`);
    /// stores may override it with one load/sort pass. Implementations must
    /// preserve item identity, ordering, and available outputs. The JSON store
    /// quarantines corrupt payloads and bounds retained missing records.
    func loadRefreshedItems() throws -> [OutputInboxItem]
}

public extension OutputInboxStore {
    func loadRefreshedItems() throws -> [OutputInboxItem] {
        try refreshAvailability()
        return try listItems()
    }

    /// Safe default: skip the BPM write.
    ///
    /// Fake/no-op stores inherit this so they can never resurrect a removed
    /// row or overwrite newer fields. This default must never be a
    /// list-read + `updateItem` upsert: that pattern writes a stale snapshot
    /// back over the live row. Real stores override with a locked
    /// load-check-patch-save.
    func patchBPMMetadata(id: UUID, expectedFileURL: URL, bpmMetadata: [String: String]) throws -> Bool {
        _ = id
        _ = expectedFileURL
        _ = bpmMetadata
        return false
    }
}
