import Foundation

public struct ProjectVersion: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    @ArchiveFileURL public var filePath: URL
    public let fileName: String
    public let modifiedAt: Date
    public let detectedVersionNumber: Int?

    public var format: ProjectFileFormat? { ProjectFileFormat(url: filePath) }
    public var applicationName: String { format?.displayName ?? "default app" }
    public var fileTypeLabel: String { format?.fileLabel ?? "Project" }

    public init(
        filePath: URL,
        fileName: String,
        modifiedAt: Date,
        detectedVersionNumber: Int? = nil
    ) {
        self._filePath = ArchiveFileURL(wrappedValue: filePath)
        self.fileName = fileName
        self.modifiedAt = modifiedAt
        self.detectedVersionNumber = detectedVersionNumber
        self.id = filePath.path
    }
}
