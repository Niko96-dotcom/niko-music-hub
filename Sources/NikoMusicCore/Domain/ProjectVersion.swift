import Foundation

public struct ProjectVersion: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let filePath: URL
    public let fileName: String
    public let modifiedAt: Date
    public let detectedVersionNumber: Int?

    public init(
        filePath: URL,
        fileName: String,
        modifiedAt: Date,
        detectedVersionNumber: Int? = nil
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.modifiedAt = modifiedAt
        self.detectedVersionNumber = detectedVersionNumber
        self.id = filePath.path
    }
}
