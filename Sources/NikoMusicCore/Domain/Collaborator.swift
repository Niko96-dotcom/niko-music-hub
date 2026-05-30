import Foundation

public struct Collaborator: Identifiable, Equatable, Sendable, Codable, Hashable {
    public let id: String
    public var displayName: String
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, displayName: String, updatedAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.updatedAt = updatedAt
    }
}
