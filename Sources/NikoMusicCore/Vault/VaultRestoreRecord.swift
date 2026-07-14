import Foundation

public enum VaultRestorePhase: String, CaseIterable, Codable, Sendable {
    case materializingArchive
    case copyingToActiveStaging
    case verifyingActiveStaging
    case promotingActiveCopy
    case persistingActiveLocation
    case openingInCubase
}

public struct VaultRestoreRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: ProjectID
    public let archiveGenerationURL: URL
    public let stagingURL: URL
    public let destinationURL: URL
    public let manifest: VaultManifest
    public var phase: VaultRestorePhase
    public var catalogLocationPersisted: Bool
    public var completedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    public var error: String?

    public init(
        id: UUID = UUID(),
        projectID: ProjectID,
        archiveGenerationURL: URL,
        stagingURL: URL,
        destinationURL: URL,
        manifest: VaultManifest,
        phase: VaultRestorePhase = .materializingArchive,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.archiveGenerationURL = archiveGenerationURL
        self.stagingURL = stagingURL
        self.destinationURL = destinationURL
        self.manifest = manifest
        self.phase = phase
        self.catalogLocationPersisted = false
        self.completedAt = nil
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.error = nil
    }
}

public protocol VaultArchiveGenerationResolving: Sendable {
    func verifiedArchiveGeneration(projectID: ProjectID) throws -> VaultTransferRecord?
}

public protocol VaultRestoreStoring: Sendable {
    func saveRestore(_ record: VaultRestoreRecord) throws
    func restoreRecord(id: UUID) throws -> VaultRestoreRecord?
    func recoverableRestoreRecords() throws -> [VaultRestoreRecord]
}

public protocol ActiveProjectLocationPersisting: Sendable {
    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws
}

public protocol VaultProjectOpening: Sendable {
    @discardableResult
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult?
}
