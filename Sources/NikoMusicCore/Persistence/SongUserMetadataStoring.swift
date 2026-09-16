import Foundation

public protocol SongUserMetadataStoring: Sendable {
    func loadAll() throws -> [String: SongUserMetadata]
    func upsert(_ metadata: SongUserMetadata) throws
    func upsertAll(_ metadata: [SongUserMetadata]) throws
}

/// Optional capability: stores that record workflow status transitions expose
/// them for analytics (per-stage dwell time) and per-song history UI.
/// The SQLite store conforms.
public protocol WorkflowStatusHistoryReading: Sendable {
    func loadAllStatusHistory() throws -> [WorkflowStatusChange]
    func statusHistory(forSongID songID: String) throws -> [WorkflowStatusChange]
}
