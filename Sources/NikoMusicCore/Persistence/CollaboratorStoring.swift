import Foundation

public protocol CollaboratorStoring: Sendable {
    func loadAll() throws -> [Collaborator]
    func upsert(_ collaborator: Collaborator) throws
    func delete(id: String) throws
}
