import Foundation

public enum PreviewFolderRole: String, Codable, Sendable, Hashable {
    case mixdown
    case stems
    case samples
    case root
    case other
}

public enum PreviewDetectedRole: String, Codable, Sendable, Hashable {
    case mainMix
    case master
    case preview
    case instrumental
    case acapella
    case stems
    case unknown
}

public struct PreviewCandidate: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    @ArchiveFileURL public var filePath: URL
    public let fileName: String
    public let folderRole: PreviewFolderRole
    public let modifiedAt: Date
    public let detectedRole: PreviewDetectedRole
    public let fileExtension: String
    public let detectedVersionNumber: Int?
    public let durationSeconds: Double?
    /// Derived on every rank: revisions are comparable only within a named delivery family.
    public var namedDeliveryModifiedAt: Date?
    public var confidenceScore: Double
    public var confidenceReasons: [String]

    private enum CodingKeys: String, CodingKey {
        case id, filePath, fileName, folderRole, modifiedAt, detectedRole, fileExtension
        case detectedVersionNumber, durationSeconds, namedDeliveryModifiedAt, confidenceScore, confidenceReasons
    }

    /// Decodes exactly what the synthesized decoder would, but shares the reasons list with every other candidate
    /// that has the same one (`ConfidenceReasonPool`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        _filePath = ArchiveFileURL(wrappedValue: try container.decode(URL.self, forKey: .filePath))
        fileName = try container.decode(String.self, forKey: .fileName)
        folderRole = try container.decode(PreviewFolderRole.self, forKey: .folderRole)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        detectedRole = try container.decode(PreviewDetectedRole.self, forKey: .detectedRole)
        fileExtension = try container.decode(String.self, forKey: .fileExtension)
        detectedVersionNumber = try container.decodeIfPresent(Int.self, forKey: .detectedVersionNumber)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        namedDeliveryModifiedAt = try container.decodeIfPresent(Date.self, forKey: .namedDeliveryModifiedAt)
        confidenceScore = try container.decode(Double.self, forKey: .confidenceScore)
        confidenceReasons = ConfidenceReasonPool.shared.canonical(try container.decode([String].self, forKey: .confidenceReasons))
    }

    public init(
        filePath: URL,
        fileName: String,
        folderRole: PreviewFolderRole,
        modifiedAt: Date,
        detectedRole: PreviewDetectedRole,
        fileExtension: String? = nil,
        detectedVersionNumber: Int? = nil,
        durationSeconds: Double? = nil,
        confidenceScore: Double = 0,
        confidenceReasons: [String] = []
    ) {
        self._filePath = ArchiveFileURL(wrappedValue: filePath)
        self.fileName = fileName
        self.folderRole = folderRole
        self.modifiedAt = modifiedAt
        self.detectedRole = detectedRole
        self.fileExtension = fileExtension ?? filePath.pathExtension.lowercased()
        self.detectedVersionNumber = detectedVersionNumber
        self.durationSeconds = durationSeconds
        self.confidenceScore = confidenceScore
        self.confidenceReasons = confidenceReasons
        self.id = filePath.path
    }
}
