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
    public var projectionSupplement: VaultProjectionSupplement?
    public var state: VaultTransferState
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var retryCount: Int
    public var nextRetryAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    public var error: VaultTransferError?
    public var durability: VaultDurability?
    public var supersededBy: UUID?
    public var preservedActiveCopies: [URL]?

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
        self.projectionSupplement = nil
        self.state = state
        self.completedBytes = 0
        self.totalBytes = 0
        self.retryCount = 0
        self.nextRetryAt = nil
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.error = nil
        self.durability = nil
        self.supersededBy = nil
        self.preservedActiveCopies = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, sourceURL, stagingURL, destinationURL
        case manifestID, manifest, projectionSupplement, state, completedBytes, totalBytes, retryCount
        case nextRetryAt, createdAt, updatedAt, error, durability, supersededBy, preservedActiveCopies
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        projectID = try values.decode(ProjectID.self, forKey: .projectID)
        sourceURL = try values.decode(URL.self, forKey: .sourceURL)
        stagingURL = try values.decode(URL.self, forKey: .stagingURL)
        destinationURL = try values.decode(URL.self, forKey: .destinationURL)
        manifestID = try values.decodeIfPresent(UUID.self, forKey: .manifestID)
        manifest = try values.decodeIfPresent(VaultManifest.self, forKey: .manifest)
        projectionSupplement = try values.decodeIfPresent(
            VaultProjectionSupplement.self,
            forKey: .projectionSupplement
        )
        state = try values.decode(VaultTransferState.self, forKey: .state)
        completedBytes = try values.decode(Int64.self, forKey: .completedBytes)
        totalBytes = try values.decode(Int64.self, forKey: .totalBytes)
        retryCount = try values.decode(Int.self, forKey: .retryCount)
        nextRetryAt = try values.decodeIfPresent(Date.self, forKey: .nextRetryAt)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        error = try values.decodeIfPresent(VaultTransferError.self, forKey: .error)
        durability = try values.decodeIfPresent(VaultDurability.self, forKey: .durability)
        supersededBy = try values.decodeIfPresent(UUID.self, forKey: .supersededBy)
        preservedActiveCopies = try values.decodeIfPresent([URL].self, forKey: .preservedActiveCopies)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(projectID, forKey: .projectID)
        try values.encode(sourceURL, forKey: .sourceURL)
        try values.encode(stagingURL, forKey: .stagingURL)
        try values.encode(destinationURL, forKey: .destinationURL)
        try values.encodeIfPresent(manifestID, forKey: .manifestID)
        try values.encodeIfPresent(manifest, forKey: .manifest)
        try values.encodeIfPresent(projectionSupplement, forKey: .projectionSupplement)
        try values.encode(state, forKey: .state)
        try values.encode(completedBytes, forKey: .completedBytes)
        try values.encode(totalBytes, forKey: .totalBytes)
        try values.encode(retryCount, forKey: .retryCount)
        try values.encodeIfPresent(nextRetryAt, forKey: .nextRetryAt)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encodeIfPresent(error, forKey: .error)
        try values.encodeIfPresent(durability, forKey: .durability)
        try values.encodeIfPresent(supersededBy, forKey: .supersededBy)
        try values.encodeIfPresent(preservedActiveCopies, forKey: .preservedActiveCopies)
    }
}

public enum VaultTransferClaimResult: Equatable, Sendable {
    case claimed(VaultTransferRecord)
    case existing(VaultTransferRecord)
}

public struct VaultTransferRecoveryPolicy: Equatable, Sendable {
    public static let production = VaultTransferRecoveryPolicy(
        maximumAutomaticAttempts: 5,
        initialBackoff: 15 * 60,
        maximumBackoff: 24 * 60 * 60
    )

    public let maximumAutomaticAttempts: Int
    public let initialBackoff: TimeInterval
    public let maximumBackoff: TimeInterval

    public init(
        maximumAutomaticAttempts: Int,
        initialBackoff: TimeInterval,
        maximumBackoff: TimeInterval
    ) {
        self.maximumAutomaticAttempts = max(1, maximumAutomaticAttempts)
        self.initialBackoff = max(1, initialBackoff)
        self.maximumBackoff = max(self.initialBackoff, maximumBackoff)
    }

    public func permitsAutomaticAttempt(for record: VaultTransferRecord, at date: Date) -> Bool {
        guard record.retryCount < maximumAutomaticAttempts else { return false }
        guard let nextRetryAt = record.nextRetryAt else { return true }
        return nextRetryAt <= date
    }

    /// Choose the same incomplete transfer for both execution and timer scheduling.
    /// Filter eligibility only after selection: an older retry must not bypass a
    /// newer transfer's backoff, exhausted budget, or manual-review requirement.
    public static func candidates(from incompleteRecords: [VaultTransferRecord]) -> [VaultTransferRecord] {
        Dictionary(grouping: incompleteRecords, by: \.projectID).compactMap { _, records in
            records.max(by: isLowerRecoveryPriority)
        }.sorted { $0.updatedAt < $1.updatedAt }
    }

    private static func isLowerRecoveryPriority(
        _ lhs: VaultTransferRecord,
        _ rhs: VaultTransferRecord
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        // An in-progress phase retains a more precise resume point than a failure.
        if lhs.state == .failedRecoverable, rhs.state != .failedRecoverable { return true }
        if lhs.state != .failedRecoverable, rhs.state == .failedRecoverable { return false }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    public func nextRetryDate(afterFailedAttempt attemptCount: Int, at date: Date) -> Date {
        var delay = initialBackoff
        for _ in 1..<max(1, min(attemptCount, maximumAutomaticAttempts)) {
            delay = min(delay * 2, maximumBackoff)
        }
        return date.addingTimeInterval(delay)
    }
}

public protocol VaultTransferStoring: Sendable {
    func save(_ record: VaultTransferRecord) throws
    func claimTransfer(_ record: VaultTransferRecord) throws -> VaultTransferClaimResult
    func record(id: UUID) throws -> VaultTransferRecord?
    func recoverableRecords() throws -> [VaultTransferRecord]
    func allTransferRecords() throws -> [VaultTransferRecord]
}

public protocol VaultProjectionSupplementStoring: Sendable {
    func record(id: UUID) throws -> VaultTransferRecord?

    func compareAndSetProjectionSupplement(
        _ supplement: VaultProjectionSupplement,
        transferID: UUID,
        expectedManifest: VaultManifest,
        expectedDestinationURL: URL,
        expectedState: VaultTransferState
    ) throws -> VaultTransferRecord
}

public extension VaultTransferStoring {
    func claimTransfer(_ record: VaultTransferRecord) throws -> VaultTransferClaimResult {
        try save(record)
        return .claimed(record)
    }

    func allTransferRecords() throws -> [VaultTransferRecord] {
        try recoverableRecords()
    }
}
