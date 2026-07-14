import Foundation

public struct VaultTransferError: Codable, Equatable, Sendable {
    public let origin: VaultTransferState
    public let reason: VaultFailureReason
    public let message: String

    public init(origin: VaultTransferState, reason: VaultFailureReason, message: String) {
        self.origin = origin
        self.reason = reason
        self.message = message
    }
}

public struct VaultTransferRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: ProjectID
    public var sourceURL: URL
    public var stagingURL: URL
    public var destinationURL: URL
    public var manifestID: UUID?
    public var manifest: VaultManifest?
    public var state: VaultTransferState
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var retryCount: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var error: VaultTransferError?
    public var durability: VaultDurability?

    public init(
        id: UUID = UUID(),
        projectID: ProjectID,
        sourceURL: URL,
        stagingURL: URL,
        destinationURL: URL,
        state: VaultTransferState = .activeLocal,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.stagingURL = stagingURL
        self.destinationURL = destinationURL
        self.manifestID = nil
        self.manifest = nil
        self.state = state
        self.completedBytes = 0
        self.totalBytes = 0
        self.retryCount = 0
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.error = nil
        self.durability = nil
    }
}

public protocol VaultTransferStoring: Sendable {
    func save(_ record: VaultTransferRecord) throws
    func record(id: UUID) throws -> VaultTransferRecord?
    func recoverableRecords() throws -> [VaultTransferRecord]
}
