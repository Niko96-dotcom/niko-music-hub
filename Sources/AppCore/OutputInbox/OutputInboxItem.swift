import Foundation

public enum OutputInboxItemStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case available
    case missing
    case failed
}

public struct OutputInboxItem: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var fileURL: URL
    public var sourceToolID: ToolFeatureID
    public var createdAt: Date
    public var status: OutputInboxItemStatus
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        sourceToolID: ToolFeatureID,
        createdAt: Date = Date(),
        status: OutputInboxItemStatus = .pending,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.fileURL = fileURL
        self.sourceToolID = sourceToolID
        self.createdAt = createdAt
        self.status = status
        self.metadata = metadata
    }
}
