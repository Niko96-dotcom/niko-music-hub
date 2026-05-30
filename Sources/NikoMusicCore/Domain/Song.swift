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
    /// App-owned display override; never renames `folderPath` on disk.
    public var virtualTitle: String?
    public var aliases: [String]
    /// App-owned searchable note (distinct from read-only sidecar `notes.txt`).
    public var appNote: String?
    public var previewSelectionMode: PreviewSelectionMode
    public var ignoredPreviewCandidateIDs: [String]
    public var collaboratorIDs: [String]
    /// Resolved at merge time for search; not persisted in the archive index snapshot.
    public var collaboratorNames: [String]
    public var isIgnored: Bool
    public var cprSelectionMode: CPRSelectionMode
    public var manualMainCPRID: String?
    public var ignoredCPRVersionIDs: [String]

    public var effectiveDisplayTitle: String {
        if let virtualTitle {
            let trimmed = virtualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return displayTitle
    }

    /// True when stems-like exports are detected (SPEC §10 Has Stems shelf).
    public var hasStems: Bool {
        previewCandidates.contains {
            $0.folderRole == .stems || $0.detectedRole == .stems
        }
    }

    /// Visible CPR versions after user ignores.
    public var visibleProjectVersions: [ProjectVersion] {
        projectVersions.filter { !ignoredCPRVersionIDs.contains($0.id) }
    }

    /// Effective main CPR after manual/auto selection and ignores.
    public var effectiveLatestCPR: ProjectVersion? {
        let visible = visibleProjectVersions
        switch cprSelectionMode {
        case .manual:
            if let manualID = manualMainCPRID,
               let manual = visible.first(where: { $0.id == manualID }) {
                return manual
            }
            fallthrough
        case .auto:
            if let latest = latestCPR, visible.contains(where: { $0.id == latest.id }) {
                return latest
            }
            return visible.max(by: { $0.modifiedAt < $1.modifiedAt })
        }
    }

    public init(
        folderPath: URL,
        originalFolderName: String,
        displayTitle: String,
        projectVersions: [ProjectVersion] = [],
        previewCandidates: [PreviewCandidate] = [],
        scanWarnings: [String] = [],
        sidecarNotes: String? = nil,
        mainPreviewCandidateID: String? = nil,
        latestCPR: ProjectVersion? = nil,
        virtualTitle: String? = nil,
        aliases: [String] = [],
        appNote: String? = nil,
        previewSelectionMode: PreviewSelectionMode = .auto,
        ignoredPreviewCandidateIDs: [String] = [],
        collaboratorIDs: [String] = [],
        collaboratorNames: [String] = [],
        isIgnored: Bool = false,
        cprSelectionMode: CPRSelectionMode = .auto,
        manualMainCPRID: String? = nil,
        ignoredCPRVersionIDs: [String] = []
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
        self.virtualTitle = virtualTitle
        self.aliases = aliases
        self.appNote = appNote
        self.previewSelectionMode = previewSelectionMode
        self.ignoredPreviewCandidateIDs = ignoredPreviewCandidateIDs
        self.collaboratorIDs = collaboratorIDs
        self.collaboratorNames = collaboratorNames
        self.isIgnored = isIgnored
        self.cprSelectionMode = cprSelectionMode
        self.manualMainCPRID = manualMainCPRID
        self.ignoredCPRVersionIDs = ignoredCPRVersionIDs
        self.id = folderPath.standardizedFileURL.path
    }

    /// Scan warnings safe for on-screen display (redacts embedded home paths).
    public func displayScanWarnings(homeDirectory: String? = nil) -> [String] {
        scanWarnings.map {
            DiagnosticsPathRedactor.redactPathsInText($0, homeDirectory: homeDirectory)
        }
    }

    /// Sidecar `notes.txt` text safe for on-screen display (redacts embedded home paths).
    public func displaySidecarNotes(homeDirectory: String? = nil) -> String? {
        guard let sidecarNotes else { return nil }
        return DiagnosticsPathRedactor.redactPathsInText(sidecarNotes, homeDirectory: homeDirectory)
    }

    /// Redacts a CPR/open path for song detail and cards.
    public static func displayDryRunPath(_ path: String, homeDirectory: String? = nil) -> String {
        DiagnosticsPathRedactor.redact(path, homeDirectory: homeDirectory)
    }

    private enum CodingKeys: String, CodingKey {
        case folderPath
        case originalFolderName
        case displayTitle
        case projectVersions
        case previewCandidates
        case scanWarnings
        case sidecarNotes
        case mainPreviewCandidateID
        case latestCPR
        case virtualTitle
        case aliases
        case appNote
        case previewSelectionMode
        case ignoredPreviewCandidateIDs
        case collaboratorIDs
        case collaboratorNames
        case isIgnored
        case cprSelectionMode
        case manualMainCPRID
        case ignoredCPRVersionIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderPath = try container.decode(URL.self, forKey: .folderPath)
        originalFolderName = try container.decode(String.self, forKey: .originalFolderName)
        displayTitle = try container.decode(String.self, forKey: .displayTitle)
        projectVersions = try container.decodeIfPresent([ProjectVersion].self, forKey: .projectVersions) ?? []
        previewCandidates = try container.decodeIfPresent([PreviewCandidate].self, forKey: .previewCandidates) ?? []
        scanWarnings = try container.decodeIfPresent([String].self, forKey: .scanWarnings) ?? []
        sidecarNotes = try container.decodeIfPresent(String.self, forKey: .sidecarNotes)
        mainPreviewCandidateID = try container.decodeIfPresent(String.self, forKey: .mainPreviewCandidateID)
        latestCPR = try container.decodeIfPresent(ProjectVersion.self, forKey: .latestCPR)
        virtualTitle = try container.decodeIfPresent(String.self, forKey: .virtualTitle)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        appNote = try container.decodeIfPresent(String.self, forKey: .appNote)
        previewSelectionMode = try container.decodeIfPresent(PreviewSelectionMode.self, forKey: .previewSelectionMode) ?? .auto
        ignoredPreviewCandidateIDs = try container.decodeIfPresent([String].self, forKey: .ignoredPreviewCandidateIDs) ?? []
        collaboratorIDs = try container.decodeIfPresent([String].self, forKey: .collaboratorIDs) ?? []
        collaboratorNames = try container.decodeIfPresent([String].self, forKey: .collaboratorNames) ?? []
        isIgnored = try container.decodeIfPresent(Bool.self, forKey: .isIgnored) ?? false
        cprSelectionMode = try container.decodeIfPresent(CPRSelectionMode.self, forKey: .cprSelectionMode) ?? .auto
        manualMainCPRID = try container.decodeIfPresent(String.self, forKey: .manualMainCPRID)
        ignoredCPRVersionIDs = try container.decodeIfPresent([String].self, forKey: .ignoredCPRVersionIDs) ?? []
        id = folderPath.standardizedFileURL.path
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(originalFolderName, forKey: .originalFolderName)
        try container.encode(displayTitle, forKey: .displayTitle)
        try container.encode(projectVersions, forKey: .projectVersions)
        try container.encode(previewCandidates, forKey: .previewCandidates)
        try container.encode(scanWarnings, forKey: .scanWarnings)
        try container.encodeIfPresent(sidecarNotes, forKey: .sidecarNotes)
        try container.encodeIfPresent(mainPreviewCandidateID, forKey: .mainPreviewCandidateID)
        try container.encodeIfPresent(latestCPR, forKey: .latestCPR)
        try container.encodeIfPresent(virtualTitle, forKey: .virtualTitle)
        try container.encode(aliases, forKey: .aliases)
        try container.encodeIfPresent(appNote, forKey: .appNote)
        try container.encode(previewSelectionMode, forKey: .previewSelectionMode)
        try container.encode(ignoredPreviewCandidateIDs, forKey: .ignoredPreviewCandidateIDs)
        try container.encode(collaboratorIDs, forKey: .collaboratorIDs)
        try container.encode(collaboratorNames, forKey: .collaboratorNames)
        try container.encode(isIgnored, forKey: .isIgnored)
        try container.encode(cprSelectionMode, forKey: .cprSelectionMode)
        try container.encodeIfPresent(manualMainCPRID, forKey: .manualMainCPRID)
        try container.encode(ignoredCPRVersionIDs, forKey: .ignoredCPRVersionIDs)
    }
}
