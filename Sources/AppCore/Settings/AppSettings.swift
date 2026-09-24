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
    public var securityScopedBookmark: Data?

    public init(path: String, securityScopedBookmark: Data? = nil) {
        self.path = path
        self.securityScopedBookmark = securityScopedBookmark
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case securityScopedBookmark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        securityScopedBookmark = try container.decodeIfPresent(Data.self, forKey: .securityScopedBookmark)
    }
}

public struct VaultSettings: Equatable, Codable, Sendable {
    /// Legacy rollout gate. Preserved for decode/encode compatibility and for
    /// out-of-scope consumers (`FeatureArchiveBrowser` capture pre-selection,
    /// DEBUG relaunch proof) until they migrate to `spaceIntent`. New UI and
    /// the owned runtime admission prefer `spaceIntent`; policy honors either
    /// so upgrades neither broaden nor narrow stored permissions.
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

    /// User-meaningful choice shown in Settings instead of rollout modes.
    /// `keepCopy` keeps the Active folder after a verified archive;
    /// `freeSpace` allows the Active folder to be removed, but only after an
    /// explicit per-operation confirmation plus the existing backup,
    /// Emergency Stop, Keep Local, and activity gates.
    public enum SpaceIntent: String, Codable, CaseIterable, Sendable {
        case keepCopy
        case freeSpace

        public var label: String {
            switch self {
            case .keepCopy: "Keep a verified copy"
            case .freeSpace: "Archive and free up space"
            }
        }

        public var description: String {
            switch self {
            case .keepCopy: "Archiving keeps the Active folder in place."
            case .freeSpace: "Archiving can remove the Active folder after you confirm."
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
    /// Legacy field: decoded, encoded, and honored by policy (see `SpaceIntent`
    /// migration), but no longer presented in Settings.
    public var rolloutStage: RolloutStage
    /// User-meaningful successor to `rolloutStage`. Persisted safely; missing
    /// keys decode from the legacy rollout so upgrades perform no file
    /// operations and legacy copy-only users never acquire removal permission.
    public var spaceIntent: SpaceIntent
    /// Independent, persisted stop control checked in addition to the master and
    /// automatic-archiving switches.
    public var automationEmergencyStop: Bool
    public var independentBackupConfirmed: Bool
    public var lastSuccessfulVerificationAt: Date?
    public var lastRestoreDrillAt: Date?
    /// App metadata only. Paths are stable scan identifiers; pinning never writes
    /// into or changes a project folder.
    public var keepLocalProjectIDs: Set<String>
    /// Durable Keep Local review obligation. Set by settings repair when the
    /// pin list (or the whole Vault/settings blob) could not be read, so pins
    /// may be missing. While true, every active-copy removal path refuses at
    /// the live runtime admission gate — even with Emergency Stop cleared —
    /// until the user completes Review Keep Local in Settings. Copy-only
    /// transfers stay allowed. Missing keys decode as false; a present
    /// malformed value fails decode so repair salvages it to true.
    public var keepLocalReviewRequired: Bool

    public init(
        isEnabled: Bool = false,
        activeRootID: UUID? = nil,
        archiveRootID: UUID? = nil,
        automaticArchiving: Bool = false,
        inactivityDays: Int = 30,
        minimumFreeSpaceGiB: Int = 120,
        transferFreeSpaceReserveGiB: Int = 5,
        keepPreviousGenerationDays: Int = 30,
        launchAtLogin: Bool = true,
        rolloutStage: RolloutStage = .disabled,
        spaceIntent: SpaceIntent? = nil,
        automationEmergencyStop: Bool = false,
        independentBackupConfirmed: Bool = false,
        lastSuccessfulVerificationAt: Date? = nil,
        lastRestoreDrillAt: Date? = nil,
        keepLocalProjectIDs: Set<String> = [],
        keepLocalReviewRequired: Bool = false
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
        // An explicit intent always wins; otherwise derive from the legacy
        // rollout so a missing key can never escalate a copy-only install.
        self.spaceIntent = spaceIntent ?? Self.migratedIntent(from: rolloutStage)
        self.automationEmergencyStop = automationEmergencyStop
        self.independentBackupConfirmed = independentBackupConfirmed
        self.lastSuccessfulVerificationAt = lastSuccessfulVerificationAt
        self.lastRestoreDrillAt = lastRestoreDrillAt
        self.keepLocalProjectIDs = keepLocalProjectIDs
        self.keepLocalReviewRequired = keepLocalReviewRequired
    }

    /// Pure value mapping used by both the memberwise init and the decoder.
    /// `friends` expressed a desire for removal (still gated on the backup
    /// acknowledgement at execution), so it maps to `freeSpace`; every other
    /// legacy value — including `disabled` and unknown/missing — maps to the
    /// safe `keepCopy`. Performs no file operations.
    public static func migratedIntent(from stage: RolloutStage) -> SpaceIntent {
        stage == .friends ? .freeSpace : .keepCopy
    }

    /// Records an explicit user intent choice and keeps the legacy rollout in
    /// sync for old builds and out-of-scope consumers. Downgrading to
    /// `keepCopy` steps `friends` back to `privateBeta` (copy-only when
    /// enabled); it never flips a stored `disabled` on, so the disabled state
    /// is preserved. Upgrading to `freeSpace` records `friends`.
    public mutating func setSpaceIntent(_ intent: SpaceIntent) {
        spaceIntent = intent
        switch intent {
        case .freeSpace:
            if rolloutStage != .friends {
                rolloutStage = .friends
            }
        case .keepCopy:
            if rolloutStage == .friends {
                rolloutStage = .privateBeta
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, activeRootID, archiveRootID, automaticArchiving
        case inactivityDays, minimumFreeSpaceGiB, transferFreeSpaceReserveGiB, keepPreviousGenerationDays, launchAtLogin
        case rolloutStage, spaceIntent, automationEmergencyStop, independentBackupConfirmed
        case lastSuccessfulVerificationAt, lastRestoreDrillAt
        case keepLocalProjectIDs
        case keepLocalReviewRequired
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Fail-closed on present malformed nonoptional values (S1): a missing
        // key decodes to its historical default/migration, but a present
        // corrupt value — including an explicit null — throws via `decode`
        // (not `decodeIfPresent`) so `updateSettings` cannot persist defaults
        // over stored pins and confirmations. Truly optional fields (root IDs,
        // dates) keep `decodeIfPresent` so missing/null stay nil.
        if values.contains(.isEnabled) {
            isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        } else {
            isEnabled = false
        }
        activeRootID = try values.decodeIfPresent(UUID.self, forKey: .activeRootID)
        archiveRootID = try values.decodeIfPresent(UUID.self, forKey: .archiveRootID)
        // Background inactivity/disk-pressure scheduling is independent
        // OPT-IN: missing keys decode as off. An explicit stored `true` is
        // preserved.
        if values.contains(.automaticArchiving) {
            automaticArchiving = try values.decode(Bool.self, forKey: .automaticArchiving)
        } else {
            automaticArchiving = false
        }
        if values.contains(.inactivityDays) {
            inactivityDays = try values.decode(Int.self, forKey: .inactivityDays)
        } else {
            inactivityDays = 30
        }
        if values.contains(.minimumFreeSpaceGiB) {
            minimumFreeSpaceGiB = try values.decode(Int.self, forKey: .minimumFreeSpaceGiB)
        } else {
            minimumFreeSpaceGiB = 120
        }
        if values.contains(.transferFreeSpaceReserveGiB) {
            transferFreeSpaceReserveGiB = try values.decode(Int.self, forKey: .transferFreeSpaceReserveGiB)
        } else {
            transferFreeSpaceReserveGiB = 5
        }
        if values.contains(.keepPreviousGenerationDays) {
            keepPreviousGenerationDays = try values.decode(Int.self, forKey: .keepPreviousGenerationDays)
        } else {
            keepPreviousGenerationDays = 30
        }
        if values.contains(.launchAtLogin) {
            launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin)
        } else {
            launchAtLogin = true
        }
        if values.contains(.rolloutStage) {
            rolloutStage = try values.decode(RolloutStage.self, forKey: .rolloutStage)
        } else {
            rolloutStage = .disabled
        }
        // The persisted intent is authoritative. Only a missing intent key
        // migrates from the legacy rollout; a present value decodes strictly
        // so corrupt input — including an explicit null — fails this decode
        // instead of inferring free-space permission. `AppSettings` propagates
        // that failure so an unrelated edit cannot persist vault defaults over
        // stored pins and confirmations.
        if values.contains(.spaceIntent) {
            spaceIntent = try values.decode(SpaceIntent.self, forKey: .spaceIntent)
        } else {
            spaceIntent = Self.migratedIntent(from: rolloutStage)
        }
        if values.contains(.automationEmergencyStop) {
            automationEmergencyStop = try values.decode(Bool.self, forKey: .automationEmergencyStop)
        } else {
            automationEmergencyStop = false
        }
        if values.contains(.independentBackupConfirmed) {
            independentBackupConfirmed = try values.decode(Bool.self, forKey: .independentBackupConfirmed)
        } else {
            independentBackupConfirmed = false
        }
        lastSuccessfulVerificationAt = try values.decodeIfPresent(Date.self, forKey: .lastSuccessfulVerificationAt)
        lastRestoreDrillAt = try values.decodeIfPresent(Date.self, forKey: .lastRestoreDrillAt)
        if values.contains(.keepLocalProjectIDs) {
            keepLocalProjectIDs = try values.decode(Set<String>.self, forKey: .keepLocalProjectIDs)
        } else {
            keepLocalProjectIDs = []
        }
        // Durable review obligation: a missing key means no repair ever
        // flagged the pins (false), but a present corrupt value — including
        // an explicit null — throws so repair salvages it to true.
        if values.contains(.keepLocalReviewRequired) {
            keepLocalReviewRequired = try values.decode(Bool.self, forKey: .keepLocalReviewRequired)
        } else {
            keepLocalReviewRequired = false
        }
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
    /// First-run helper-tool Set Up sheet was shown. Missing keys decode as `false`.
    public var setupAssistantShown: Bool

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
        case setupAssistantShown
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
        showMenuBarExtra: Bool = true,
        setupAssistantShown: Bool = false
    ) {
        self.outputFolder = outputFolder
        self.audioPreset = audioPreset
        self.helperTools = helperTools
        self.maxRecordingDurationMinutes = maxRecordingDurationMinutes
        self.musicRoots = musicRoots.isEmpty
            ? archiveRoots.map {
                StoredMusicRoot(
                    role: .scanOnly,
                    url: $0.url,
                    securityScopedBookmark: $0.securityScopedBookmark
                )
            }
            : musicRoots
        self.vault = vault
        self.appearance = appearance
        self.archiveOnboardingCompleted = archiveOnboardingCompleted
        self.scanExclusionTerms = scanExclusionTerms
        self.showMenuBarExtra = showMenuBarExtra
        self.setupAssistantShown = setupAssistantShown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Fail-closed on present malformed values (S1): a missing key decodes
        // to its historical default/migration, but a present corrupt value
        // throws so `UserDefaultsSettingsStore.updateSettings` cannot load
        // silently-defaulted settings and persist them over stored pins and
        // confirmations. `contains` distinguishes missing from explicit null;
        // `decode` (not `decodeIfPresent`) makes explicit null throw.
        if container.contains(.outputFolder) {
            outputFolder = try container.decode(StoredFolderLocation.self, forKey: .outputFolder)
        } else {
            outputFolder = StoredFolderLocation()
        }
        if container.contains(.audioPreset) {
            audioPreset = try container.decode(AudioPreset.self, forKey: .audioPreset)
        } else {
            audioPreset = .cubaseDefault
        }
        if container.contains(.helperTools) {
            helperTools = try container.decode(HelperToolSettings.self, forKey: .helperTools)
        } else {
            helperTools = HelperToolSettings()
        }
        if container.contains(.maxRecordingDurationMinutes) {
            maxRecordingDurationMinutes = try container.decode(Int.self, forKey: .maxRecordingDurationMinutes)
        } else {
            maxRecordingDurationMinutes = 30
        }
        if container.contains(.musicRoots) {
            musicRoots = try container.decode([StoredMusicRoot].self, forKey: .musicRoots)
        } else if container.contains(.archiveRoots) {
            let legacyRoots = try container.decode([StoredArchiveRoot].self, forKey: .archiveRoots)
            musicRoots = legacyRoots.map {
                StoredMusicRoot(
                    role: .scanOnly,
                    url: $0.url,
                    securityScopedBookmark: $0.securityScopedBookmark
                )
            }
        } else {
            musicRoots = []
        }
        if container.contains(.vault) {
            vault = try container.decode(VaultSettings.self, forKey: .vault)
        } else {
            vault = VaultSettings()
        }
        if container.contains(.appearance) {
            appearance = try container.decode(AppAppearance.self, forKey: .appearance)
        } else {
            appearance = .followSystem
        }
        if container.contains(.archiveOnboardingCompleted) {
            archiveOnboardingCompleted = try container.decode(Bool.self, forKey: .archiveOnboardingCompleted)
        } else {
            archiveOnboardingCompleted = false
        }
        if container.contains(.scanExclusionTerms) {
            scanExclusionTerms = try container.decode(String.self, forKey: .scanExclusionTerms)
        } else {
            scanExclusionTerms = ""
        }
        if container.contains(.showMenuBarExtra) {
            showMenuBarExtra = try container.decode(Bool.self, forKey: .showMenuBarExtra)
        } else {
            showMenuBarExtra = true
        }
        if container.contains(.setupAssistantShown) {
            setupAssistantShown = try container.decode(Bool.self, forKey: .setupAssistantShown)
        } else {
            setupAssistantShown = false
        }
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
        try container.encode(setupAssistantShown, forKey: .setupAssistantShown)
    }

    /// Compatibility surface for existing archive-browser callers. Root-list edits only
    /// replace Scan-only roots, so Vault selections are never silently reinterpreted.
    public var archiveRoots: [StoredArchiveRoot] {
        get {
            effectiveScanRoots.map {
                StoredArchiveRoot(path: $0.pathFallback, securityScopedBookmark: $0.securityScopedBookmark)
            }
        }
        set {
            let retainedVaultRoots = musicRoots.filter { $0.role != .scanOnly }
            // Stored lists can carry the same Scan-only path twice (legacy salvage,
            // hand-edited defaults); keep the first entry instead of trapping.
            let existingScanRoots = Dictionary(
                musicRoots
                    .filter { $0.role == .scanOnly }
                    .map { ($0.fallbackURL.path, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let replacementScanRoots = newValue.map { legacyRoot -> StoredMusicRoot in
                if var existing = existingScanRoots[legacyRoot.url.standardizedFileURL.path] {
                    if let bookmark = legacyRoot.securityScopedBookmark {
                        existing.securityScopedBookmark = bookmark
                    }
                    return existing
                }
                return StoredMusicRoot(
                    role: .scanOnly,
                    url: legacyRoot.url,
                    securityScopedBookmark: legacyRoot.securityScopedBookmark
                )
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
