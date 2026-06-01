import Foundation

public enum PreviewFolderRole: String, Codable, Sendable, Hashable {
    case mixdown
    case stems
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
    public let filePath: URL
    public let fileName: String
    public let folderRole: PreviewFolderRole
    public let modifiedAt: Date
    public let detectedRole: PreviewDetectedRole
    public let fileExtension: String
    public let detectedVersionNumber: Int?
    public let durationSeconds: Double?
    public var confidenceScore: Double
    public var confidenceReasons: [String]

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
        self.filePath = filePath
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
