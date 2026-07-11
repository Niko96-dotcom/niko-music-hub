import Foundation

public protocol SongUserMetadataStoring: Sendable {
    func loadAll() throws -> [String: SongUserMetadata]
    func upsert(_ metadata: SongUserMetadata) throws
    func upsertAll(_ metadata: [SongUserMetadata]) throws
}

/// Optional capability: stores that record workflow status transitions expose
/// them for analytics (per-stage dwell time). The SQLite store conforms.
public protocol WorkflowStatusHistoryReading: Sendable {
    func loadAllStatusHistory() throws -> [WorkflowStatusChange]
}
