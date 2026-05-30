import Foundation

public protocol ArchiveIndexStoring: Sendable {
    func loadLatest() throws -> ArchiveIndexSnapshot?
    func save(_ snapshot: ArchiveIndexSnapshot) throws
    func clear() throws
}
