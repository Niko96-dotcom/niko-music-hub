import Foundation

public struct Song: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let folderPath: URL
    public let originalFolderName: String
    public let displayTitle: String
    public var projectVersions: [ProjectVersion]
    public var previewCandidates: [PreviewCandidate]
    public var scanWarnings: [String]
    /// Trimmed text from `notes.txt` at the song folder root, when present.
    public var sidecarNotes: String?
    public var mainPreviewCandidateID: String?
    public var latestCPR: ProjectVersion?

    public init(
        folderPath: URL,
        originalFolderName: String,
        displayTitle: String,
        projectVersions: [ProjectVersion] = [],
        previewCandidates: [PreviewCandidate] = [],
        scanWarnings: [String] = [],
        sidecarNotes: String? = nil,
        mainPreviewCandidateID: String? = nil,
        latestCPR: ProjectVersion? = nil
    ) {
        self.folderPath = folderPath
        self.originalFolderName = originalFolderName
        self.displayTitle = displayTitle
        self.projectVersions = projectVersions
        self.previewCandidates = previewCandidates
        self.scanWarnings = scanWarnings
        self.sidecarNotes = sidecarNotes
        self.mainPreviewCandidateID = mainPreviewCandidateID
        self.latestCPR = latestCPR
        self.id = folderPath.path
    }

    /// Scan warnings safe for on-screen display (redacts embedded home paths).
    public func displayScanWarnings(homeDirectory: String? = nil) -> [String] {
        scanWarnings.map {
            DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
        }
    }

    /// Redacts a CPR/open path for song detail and cards.
    public static func displayDryRunPath(_ path: String, homeDirectory: String? = nil) -> String {
        DiagnosticsPathRedactor.redact(path, homeDirectory: homeDirectory)
    }
}
