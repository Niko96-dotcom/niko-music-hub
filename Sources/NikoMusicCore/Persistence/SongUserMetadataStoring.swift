import Foundation

public protocol SongUserMetadataStoring: Sendable {
    func loadAll() throws -> [String: SongUserMetadata]
    func upsert(_ metadata: SongUserMetadata) throws
    func upsertAll(_ metadata: [SongUserMetadata]) throws
}

/// Per-row tolerant load outcome. `metadata` holds every row that decoded
/// cleanly; `corruptSongIDs` identifies stored rows that could not be decoded
/// and were skipped (never deleted or rewritten by the load itself).
public struct SongUserMetadataLoadReport: Sendable, Equatable {
    public let metadata: [String: SongUserMetadata]
    public let corruptSongIDs: [String]

    public init(metadata: [String: SongUserMetadata], corruptSongIDs: [String] = []) {
        self.metadata = metadata
        self.corruptSongIDs = corruptSongIDs
    }
}

/// Optional capability: stores that can decode rows independently report
/// per-row integrity instead of failing the whole load on one corrupt row.
/// Fakes that only conform to `SongUserMetadataStoring` keep working; callers
/// fall back to `loadAll()` for those.
public protocol SongUserMetadataLoadReporting: Sendable {
    func loadAllWithReport() throws -> SongUserMetadataLoadReport
}

/// Optional capability: stores that record workflow status transitions expose
/// them for analytics (per-stage dwell time) and per-song history UI.
/// The SQLite store conforms.
public protocol WorkflowStatusHistoryReading: Sendable {
    func loadAllStatusHistory() throws -> [WorkflowStatusChange]
    func statusHistory(forSongID songID: String) throws -> [WorkflowStatusChange]
}

/// Fail-closed refusal for per-row corruption. Thrown when an upsert targets a
/// song whose currently stored row is undecodable: overwriting it with values
/// defaulted from a degraded in-memory song would erase the stored title, note
/// and workflow status (and append a bogus status-history transition), so the
/// write — including any status-history insert — must not happen. Coordinators
/// pre-check known-corrupt IDs to surface a visible warning without reaching
/// the store; this error is the backstop for all other call sites.
public struct SongUserMetadataCorruptRowError: Error, Sendable, Equatable {
    public let songIDs: [String]

    public init(songIDs: [String]) {
        self.songIDs = songIDs
    }

    public init(songID: String) {
        self.songIDs = [songID]
    }
}
