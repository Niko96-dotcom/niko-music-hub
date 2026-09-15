import Foundation

public enum VaultRestorePhase: String, CaseIterable, Codable, Sendable {
    case materializingArchive
    case copyingToActiveStaging
    case verifyingActiveStaging
    case promotingActiveCopy
    case persistingActiveLocation
    case openingInCubase
    case superseded
}

public enum VaultRestoreFailureReason: String, Codable, Equatable, Sendable {
    case legacyProjectionEvidenceUnavailable
    case legacyProjectionIdentityMismatch
    case archiveTransferBindingUnavailable
    case activeDestinationIntegrityMismatch
    case archiveGenerationIntegrityMismatch
}

public struct VaultRestoreRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: ProjectID
    public let archiveGenerationURL: URL
    public var stagingURL: URL
    public let destinationURL: URL
    public let manifest: VaultManifest
    public let linkedArchiveLocation: ProjectLocation?
    public let archiveTransferID: UUID?
    public let archiveTransferState: VaultTransferState?
    public let requiresArchiveMaterialization: Bool
    public var projectionSupplement: VaultProjectionSupplement?
    public var phase: VaultRestorePhase
    public var catalogLocationPersisted: Bool
    public var completedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    public var error: String?
    public var failureReason: VaultRestoreFailureReason?
    public var supersededBy: UUID?

    public var reviewGenerationURL: URL? {
        failureReason == .legacyProjectionEvidenceUnavailable ? archiveGenerationURL : nil
    }

    public init(
        id: UUID = UUID(),
        projectID: ProjectID,
        archiveGenerationURL: URL,
        stagingURL: URL,
        destinationURL: URL,
        manifest: VaultManifest,
        linkedArchiveLocation: ProjectLocation? = nil,
        archiveTransferID: UUID? = nil,
        archiveTransferState: VaultTransferState? = nil,
        requiresArchiveMaterialization: Bool = true,
        projectionSupplement: VaultProjectionSupplement? = nil,
        phase: VaultRestorePhase = .materializingArchive,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.archiveGenerationURL = archiveGenerationURL
        self.stagingURL = stagingURL
        self.destinationURL = destinationURL
        self.manifest = manifest
        self.linkedArchiveLocation = linkedArchiveLocation
        self.archiveTransferID = archiveTransferID
        self.archiveTransferState = archiveTransferState
        self.requiresArchiveMaterialization = requiresArchiveMaterialization
        self.projectionSupplement = projectionSupplement
        self.phase = phase
        self.catalogLocationPersisted = false
        self.completedAt = nil
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.error = nil
        self.failureReason = nil
        self.supersededBy = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, archiveGenerationURL, stagingURL, destinationURL
        case linkedArchiveLocation
        case manifest, archiveTransferID, archiveTransferState, requiresArchiveMaterialization
        case projectionSupplement, phase, catalogLocationPersisted
        case completedAt, createdAt, updatedAt, error, failureReason, supersededBy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        projectID = try values.decode(ProjectID.self, forKey: .projectID)
        archiveGenerationURL = try values.decode(URL.self, forKey: .archiveGenerationURL)
        stagingURL = try values.decode(URL.self, forKey: .stagingURL)
        destinationURL = try values.decode(URL.self, forKey: .destinationURL)
        manifest = try values.decode(VaultManifest.self, forKey: .manifest)
        linkedArchiveLocation = try values.decodeIfPresent(ProjectLocation.self, forKey: .linkedArchiveLocation)
        archiveTransferID = try values.decodeIfPresent(UUID.self, forKey: .archiveTransferID)
        archiveTransferState = try values.decodeIfPresent(
            VaultTransferState.self,
            forKey: .archiveTransferState
        )
        requiresArchiveMaterialization = try values.decodeIfPresent(
            Bool.self,
            forKey: .requiresArchiveMaterialization
        ) ?? true
        projectionSupplement = try values.decodeIfPresent(
            VaultProjectionSupplement.self,
            forKey: .projectionSupplement
        )
        phase = try values.decode(VaultRestorePhase.self, forKey: .phase)
        catalogLocationPersisted = try values.decode(Bool.self, forKey: .catalogLocationPersisted)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        failureReason = try values.decodeIfPresent(
            VaultRestoreFailureReason.self,
            forKey: .failureReason
        )
        supersededBy = try values.decodeIfPresent(UUID.self, forKey: .supersededBy)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(projectID, forKey: .projectID)
        try values.encode(archiveGenerationURL, forKey: .archiveGenerationURL)
        try values.encode(stagingURL, forKey: .stagingURL)
        try values.encode(destinationURL, forKey: .destinationURL)
        try values.encode(manifest, forKey: .manifest)
        try values.encodeIfPresent(linkedArchiveLocation, forKey: .linkedArchiveLocation)
        try values.encodeIfPresent(archiveTransferID, forKey: .archiveTransferID)
        try values.encodeIfPresent(archiveTransferState, forKey: .archiveTransferState)
        try values.encode(requiresArchiveMaterialization, forKey: .requiresArchiveMaterialization)
        try values.encodeIfPresent(projectionSupplement, forKey: .projectionSupplement)
        try values.encode(phase, forKey: .phase)
        try values.encode(catalogLocationPersisted, forKey: .catalogLocationPersisted)
        try values.encodeIfPresent(completedAt, forKey: .completedAt)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encodeIfPresent(error, forKey: .error)
        try values.encodeIfPresent(failureReason, forKey: .failureReason)
        try values.encodeIfPresent(supersededBy, forKey: .supersededBy)
    }
}

public protocol VaultArchiveGenerationResolving: Sendable {
    func verifiedArchiveGeneration(projectID: ProjectID) throws -> VaultTransferRecord?
}

public protocol VaultRestoreStoring: Sendable {
    func saveRestore(_ record: VaultRestoreRecord) throws
    func claimRestore(_ record: VaultRestoreRecord) throws -> VaultRestoreClaimResult
    func restoreRecord(id: UUID) throws -> VaultRestoreRecord?
    func recoverableRestoreRecords() throws -> [VaultRestoreRecord]
    func reconcileRestoreRecordsForRecovery() throws -> [VaultRestoreRecord]
}

public enum VaultRestoreClaimResult: Equatable, Sendable {
    case claimed(VaultRestoreRecord)
    case existing(VaultRestoreRecord)
}

public extension VaultRestoreStoring {
    func claimRestore(_ record: VaultRestoreRecord) throws -> VaultRestoreClaimResult {
        try saveRestore(record)
        return .claimed(record)
    }

    func reconcileRestoreRecordsForRecovery() throws -> [VaultRestoreRecord] {
        try recoverableRestoreRecords()
    }
}

public protocol ActiveProjectLocationPersisting: Sendable {
    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws
}

public protocol VaultProjectOpening: Sendable {
    @discardableResult
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult?
}
