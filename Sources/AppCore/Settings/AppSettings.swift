import Foundation
import NikoMusicCore

public struct StoredFolderLocation: Equatable, Codable, Sendable {
    public var url: URL

    public init(url: URL = Self.defaultOutputFolder) {
        self.url = url
    }

    public static var defaultOutputFolder: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Music", isDirectory: true)
            .appendingPathComponent("Niko Music Hub", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
    }
}

public struct StoredArchiveRoot: Equatable, Codable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

public struct VaultSettings: Equatable, Codable, Sendable {
    public enum RolloutStage: String, Codable, CaseIterable, Sendable {
        case disabled
        case privateBeta
        case friends

        public var label: String {
            switch self {
            case .disabled: "Off"
            case .privateBeta: "Private beta (automatic copies only)"
            case .friends: "Friends"
            }
        }
    }

    public var isEnabled: Bool
    public var activeRootID: UUID?
    public var archiveRootID: UUID?
    public var automaticArchiving: Bool
    public var inactivityDays: Int
    /// Active-volume pressure threshold that makes projects eligible for archiving.
    public var minimumFreeSpaceGiB: Int
    /// Free space to retain on the destination after a projected archive/restore write.
    public var transferFreeSpaceReserveGiB: Int
    public var keepPreviousGenerationDays: Int
    public var launchAtLogin: Bool
    /// Rollout stays explicit so a locally enabled development build cannot silently
    /// become an artist-library automation deployment.
    public var rolloutStage: RolloutStage
    /// Independent, persisted stop control checked in addition to the master and
    /// automatic-archiving switches.
    public var automationEmergencyStop: Bool
    public var independentBackupConfirmed: Bool
    public var lastSuccessfulVerificationAt: Date?
    public var lastRestoreDrillAt: Date?
    /// App metadata only. Paths are stable scan identifiers; pinning never writes
    /// into or changes a project folder.
    public var keepLocalProjectIDs: Set<String>

    public init(
        isEnabled: Bool = false,
        activeRootID: UUID? = nil,
        archiveRootID: UUID? = nil,
        automaticArchiving: Bool = true,
        inactivityDays: Int = 30,
        minimumFreeSpaceGiB: Int = 120,
        transferFreeSpaceReserveGiB: Int = 5,
        keepPreviousGenerationDays: Int = 30,
        launchAtLogin: Bool = true,
        rolloutStage: RolloutStage = .disabled,
        automationEmergencyStop: Bool = false,
        independentBackupConfirmed: Bool = false,
        lastSuccessfulVerificationAt: Date? = nil,
        lastRestoreDrillAt: Date? = nil,
        keepLocalProjectIDs: Set<String> = []
    ) {
        self.isEnabled = isEnabled
        self.activeRootID = activeRootID
        self.archiveRootID = archiveRootID
        self.automaticArchiving = automaticArchiving
        self.inactivityDays = inactivityDays
        self.minimumFreeSpaceGiB = minimumFreeSpaceGiB
        self.transferFreeSpaceReserveGiB = transferFreeSpaceReserveGiB
        self.keepPreviousGenerationDays = keepPreviousGenerationDays
        self.launchAtLogin = launchAtLogin
        self.rolloutStage = rolloutStage
        self.automationEmergencyStop = automationEmergencyStop
        self.independentBackupConfirmed = independentBackupConfirmed
        self.lastSuccessfulVerificationAt = lastSuccessfulVerificationAt
        self.lastRestoreDrillAt = lastRestoreDrillAt
        self.keepLocalProjectIDs = keepLocalProjectIDs
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, activeRootID, archiveRootID, automaticArchiving
        case inactivityDays, minimumFreeSpaceGiB, transferFreeSpaceReserveGiB, keepPreviousGenerationDays, launchAtLogin
        case rolloutStage, automationEmergencyStop, independentBackupConfirmed
        case lastSuccessfulVerificationAt, lastRestoreDrillAt
        case keepLocalProjectIDs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        activeRootID = try values.decodeIfPresent(UUID.self, forKey: .activeRootID)
        archiveRootID = try values.decodeIfPresent(UUID.self, forKey: .archiveRootID)
        automaticArchiving = try values.decodeIfPresent(Bool.self, forKey: .automaticArchiving) ?? true
        inactivityDays = try values.decodeIfPresent(Int.self, forKey: .inactivityDays) ?? 30
        minimumFreeSpaceGiB = try values.decodeIfPresent(Int.self, forKey: .minimumFreeSpaceGiB) ?? 120
        transferFreeSpaceReserveGiB = try values.decodeIfPresent(Int.self, forKey: .transferFreeSpaceReserveGiB) ?? 5
        keepPreviousGenerationDays = try values.decodeIfPresent(Int.self, forKey: .keepPreviousGenerationDays) ?? 30
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        rolloutStage = try values.decodeIfPresent(RolloutStage.self, forKey: .rolloutStage) ?? .disabled
        automationEmergencyStop = try values.decodeIfPresent(Bool.self, forKey: .automationEmergencyStop) ?? false
        independentBackupConfirmed = try values.decodeIfPresent(Bool.self, forKey: .independentBackupConfirmed) ?? false
        lastSuccessfulVerificationAt = try values.decodeIfPresent(Date.self, forKey: .lastSuccessfulVerificationAt)
        lastRestoreDrillAt = try values.decodeIfPresent(Date.self, forKey: .lastRestoreDrillAt)
        keepLocalProjectIDs = try values.decodeIfPresent(Set<String>.self, forKey: .keepLocalProjectIDs) ?? []
    }
}

public struct AppSettings: Equatable, Codable, Sendable {
    public var outputFolder: StoredFolderLocation
    public var audioPreset: AudioPreset
    public var helperTools: HelperToolSettings
    public var maxRecordingDurationMinutes: Int
    public var musicRoots: [StoredMusicRoot]
    public var vault: VaultSettings
    public var appearance: AppAppearance
    /// User completed first-run archive root onboarding (SPEC §5).
    public var archiveOnboardingCompleted: Bool
    /// Comma-separated folder-name terms to skip during archive scan (e.g. backup, tmp).
    public var scanExclusionTerms: String
    /// Menu-bar extra (waveform). Missing keys decode as `true` so 1.5.4 upgraders keep it.
    public var showMenuBarExtra: Bool

    private enum CodingKeys: String, CodingKey {
        case outputFolder
        case audioPreset
        case helperTools
        case maxRecordingDurationMinutes
        case musicRoots
        case vault
        // Decode-only compatibility with settings written before typed roots.
        case archiveRoots
        case appearance
        case archiveOnboardingCompleted
        case scanExclusionTerms
        case showMenuBarExtra
    }

    public init(
        outputFolder: StoredFolderLocation = StoredFolderLocation(),
        audioPreset: AudioPreset = .cubaseDefault,
        helperTools: HelperToolSettings = HelperToolSettings(),
        maxRecordingDurationMinutes: Int = 30,
        archiveRoots: [StoredArchiveRoot] = [],
        musicRoots: [StoredMusicRoot] = [],
        vault: VaultSettings = VaultSettings(),
        appearance: AppAppearance = .followSystem,
        archiveOnboardingCompleted: Bool = false,
        scanExclusionTerms: String = "",
        showMenuBarExtra: Bool = true
    ) {
        self.outputFolder = outputFolder
        self.audioPreset = audioPreset
        self.helperTools = helperTools
        self.maxRecordingDurationMinutes = maxRecordingDurationMinutes
        self.musicRoots = musicRoots.isEmpty
            ? archiveRoots.map { StoredMusicRoot(role: .scanOnly, url: $0.url) }
            : musicRoots
        self.vault = vault
        self.appearance = appearance
        self.archiveOnboardingCompleted = archiveOnboardingCompleted
        self.scanExclusionTerms = scanExclusionTerms
        self.showMenuBarExtra = showMenuBarExtra
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        outputFolder = (try? container.decodeIfPresent(StoredFolderLocation.self, forKey: .outputFolder)) ?? StoredFolderLocation()
        audioPreset = (try? container.decodeIfPresent(AudioPreset.self, forKey: .audioPreset)) ?? .cubaseDefault
        helperTools = (try? container.decodeIfPresent(HelperToolSettings.self, forKey: .helperTools)) ?? HelperToolSettings()
        maxRecordingDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .maxRecordingDurationMinutes)) ?? 30
        if let typedRoots = try container.decodeIfPresent([StoredMusicRoot].self, forKey: .musicRoots) {
            musicRoots = typedRoots
        } else {
            let legacyRoots = (try? container.decodeIfPresent([StoredArchiveRoot].self, forKey: .archiveRoots)) ?? []
            musicRoots = legacyRoots.map { StoredMusicRoot(role: .scanOnly, url: $0.url) }
        }
        vault = (try? container.decodeIfPresent(VaultSettings.self, forKey: .vault)) ?? VaultSettings()
        appearance = (try? container.decodeIfPresent(AppAppearance.self, forKey: .appearance)) ?? .followSystem
        archiveOnboardingCompleted = (try? container.decodeIfPresent(Bool.self, forKey: .archiveOnboardingCompleted)) ?? false
        scanExclusionTerms = (try? container.decodeIfPresent(String.self, forKey: .scanExclusionTerms)) ?? ""
        showMenuBarExtra = (try? container.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra)) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputFolder, forKey: .outputFolder)
        try container.encode(audioPreset, forKey: .audioPreset)
        try container.encode(helperTools, forKey: .helperTools)
        try container.encode(maxRecordingDurationMinutes, forKey: .maxRecordingDurationMinutes)
        try container.encode(musicRoots, forKey: .musicRoots)
        try container.encode(vault, forKey: .vault)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(archiveOnboardingCompleted, forKey: .archiveOnboardingCompleted)
        try container.encode(scanExclusionTerms, forKey: .scanExclusionTerms)
        try container.encode(showMenuBarExtra, forKey: .showMenuBarExtra)
    }

    /// Compatibility surface for existing archive-browser callers. Root-list edits only
    /// replace Scan-only roots, so Vault selections are never silently reinterpreted.
    public var archiveRoots: [StoredArchiveRoot] {
        get {
            effectiveScanRoots.map { StoredArchiveRoot(path: $0.pathFallback) }
        }
        set {
            let retainedVaultRoots = musicRoots.filter { $0.role != .scanOnly }
            let existingScanRoots = Dictionary(
                uniqueKeysWithValues: musicRoots
                    .filter { $0.role == .scanOnly }
                    .map { ($0.fallbackURL.path, $0) }
            )
            let replacementScanRoots = newValue.map { legacyRoot -> StoredMusicRoot in
                existingScanRoots[legacyRoot.url.standardizedFileURL.path]
                    ?? StoredMusicRoot(role: .scanOnly, url: legacyRoot.url)
            }
            musicRoots = retainedVaultRoots + replacementScanRoots
        }
    }

    /// Vault-off browsing is exactly the legacy Scan-only list. Opting in additionally
    /// exposes the selected Active and Archive locations to the read-only browser.
    public var effectiveScanRoots: [StoredMusicRoot] {
        let eligible = musicRoots.filter { root in
            guard root.isEnabled else { return false }
            return root.role == .scanOnly || vault.isEnabled
        }
        var indexByCanonicalPath: [String: Int] = [:]
        var unique: [StoredMusicRoot] = []
        for root in eligible {
            let path = root.fallbackURL.resolvingSymlinksInPath().standardizedFileURL.path
            if let index = indexByCanonicalPath[path] {
                if Self.scanRootPriority(root, vault: vault) > Self.scanRootPriority(unique[index], vault: vault) {
                    unique[index] = root
                }
            } else {
                indexByCanonicalPath[path] = unique.count
                unique.append(root)
            }
        }
        return unique
    }

    private static func scanRootPriority(_ root: StoredMusicRoot, vault: VaultSettings) -> Int {
        if root.id == vault.activeRootID, root.role == .active { return 3 }
        if root.id == vault.archiveRootID, root.role == .archive { return 3 }
        return root.role == .scanOnly ? 1 : 2
    }

    public static let `default` = AppSettings()
}
