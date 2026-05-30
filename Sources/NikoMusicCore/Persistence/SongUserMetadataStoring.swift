import Foundation

public protocol SongUserMetadataStoring: Sendable {
    func loadAll() throws -> [String: SongUserMetadata]
    func upsert(_ metadata: SongUserMetadata) throws
    func upsertAll(_ metadata: [SongUserMetadata]) throws
}
