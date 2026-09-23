import Foundation
import NikoMusicCore

/// Explicit, user-confirmed way out of fail-closed settings (D1).
///
/// `AppSettings` decoding throws on any present-but-malformed field so an
/// unrelated save can never persist defaults over stored pins and
/// confirmations. That leaves every save failing until the blob is fixed. The
/// repair here is the only writer allowed to touch a corrupt blob, and only on
/// an explicit click: it backs up the raw bytes, keeps every field that still
/// decodes (Project Vault sub-fields individually), defaults only the broken
/// ones, and saves.
public protocol SettingsRepairing: Sendable {
    /// True when stored settings exist but no longer decode.
    func storedSettingsNeedRepair() -> Bool
    /// Backs up the raw stored blob into `backupDirectory`, then saves the
    /// salvaged settings. Returns nil (and writes nothing) when the stored
    /// settings are missing or already decode. Throws
    /// `SettingsRepairError.backupFailed` before changing anything when the
    /// backup cannot be written and read back.
    func repairStoredSettings(backupDirectory: URL, now: Date) throws -> SettingsRepairOutcome?
}

public extension SettingsRepairing {
    func repairStoredSettings(backupDirectory: URL) throws -> SettingsRepairOutcome? {
        try repairStoredSettings(backupDirectory: backupDirectory, now: Date())
    }
}

public enum SettingsRepairError: Error, Equatable, Sendable {
    case backupFailed
}

public struct SettingsRepairOutcome: Equatable, Sendable {
    public let settings: AppSettings
    /// Plain-language names of the settings that were reset to their defaults.
    public let resetFields: [String]
    /// Unreadable archive-folder entries that were dropped (the rest are kept).
    public let droppedArchiveFolderCount: Int
    /// The Keep Local pin list (or the whole Project Vault block) could not
    /// be read, so removal was paused (emergency stop on, keep-a-copy rule).
    public let vaultRemovalPaused: Bool
    public let backupURL: URL

    public init(
        settings: AppSettings,
        resetFields: [String],
        droppedArchiveFolderCount: Int,
        vaultRemovalPaused: Bool = false,
        backupURL: URL
    ) {
        self.settings = settings
        self.resetFields = resetFields
        self.droppedArchiveFolderCount = droppedArchiveFolderCount
        self.vaultRemovalPaused = vaultRemovalPaused
        self.backupURL = backupURL
    }

    public static let removalPausedMessage =
        "Keep Local list couldn't be read — Project Vault removal is paused until you review it."

    /// One plain sentence group for the user; never type names or errors.
    public var message: String {
        var parts = ["Repaired settings."]
        if !resetFields.isEmpty {
            parts.append("Reset to default: \(resetFields.joined(separator: ", ")).")
        }
        if droppedArchiveFolderCount > 0 {
            let noun = droppedArchiveFolderCount == 1 ? "archive folder" : "archive folders"
            parts.append("Removed \(droppedArchiveFolderCount) unreadable \(noun).")
        }
        if vaultRemovalPaused {
            parts.append(Self.removalPausedMessage)
        }
        parts.append("A backup was saved.")
        return parts.joined(separator: " ")
    }
}

/// Field-by-field salvage of a stored settings blob. Pure: no I/O.
enum SettingsSalvage {
    struct Result {
        var settings: AppSettings
        var resetFields: [String]
        var droppedArchiveFolderCount: Int
        var vaultRemovalPaused = false
    }

    static func salvage(_ data: Data) -> Result {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            var settings = AppSettings.default
            settings.vault = pausedVault(VaultSettings())
            return Result(
                settings: settings,
                resetFields: ["all settings"],
                droppedArchiveFolderCount: 0,
                vaultRemovalPaused: true
            )
        }
        var settings = AppSettings.default
        var reset: [String] = []
        var dropped = 0
        var removalPaused = false

        func field<T: Decodable>(_ key: String, _ label: String, _ type: T.Type, _ apply: (T) -> Void) {
            guard let raw = object[key] else { return }
            if let value = decode(type, from: raw) {
                apply(value)
            } else {
                reset.append(label)
            }
        }

        field("outputFolder", "output folder", StoredFolderLocation.self) { settings.outputFolder = $0 }
        field("audioPreset", "audio format", AudioPreset.self) { settings.audioPreset = $0 }
        field("helperTools", "helper tool locations", HelperToolSettings.self) { settings.helperTools = $0 }
        field("maxRecordingDurationMinutes", "recording length limit", Int.self) {
            settings.maxRecordingDurationMinutes = $0
        }

        if let rawRoots = object["musicRoots"] {
            if let entries = rawRoots as? [Any] {
                let decoded = entries.map { decode(StoredMusicRoot.self, from: $0) }
                settings.musicRoots = decoded.compactMap { $0 }
                dropped += decoded.count - settings.musicRoots.count
            } else {
                reset.append("archive folders")
            }
        } else if let rawLegacy = object["archiveRoots"] {
            if let entries = rawLegacy as? [Any] {
                let decoded = entries.map { decode(StoredArchiveRoot.self, from: $0) }
                let kept = decoded.compactMap { $0 }
                dropped += decoded.count - kept.count
                settings.archiveRoots = kept
            } else {
                reset.append("archive folders")
            }
        }

        if let rawVault = object["vault"] {
            if let vaultObject = rawVault as? [String: Any] {
                let salvaged = salvageVault(vaultObject)
                settings.vault = salvaged.vault
                reset.append(contentsOf: salvaged.resetFields)
                removalPaused = salvaged.removalPaused
            } else {
                // The pins and the stop inside it are gone too: pause removal.
                reset.append("Project Vault settings")
                settings.vault = pausedVault(VaultSettings())
                removalPaused = true
            }
        }

        field("appearance", "appearance", AppAppearance.self) { settings.appearance = $0 }
        field("archiveOnboardingCompleted", "archive setup status", Bool.self) {
            settings.archiveOnboardingCompleted = $0
        }
        field("scanExclusionTerms", "skipped folder names", String.self) { settings.scanExclusionTerms = $0 }
        field("showMenuBarExtra", "menu bar icon", Bool.self) { settings.showMenuBarExtra = $0 }
        field("setupAssistantShown", "setup assistant status", Bool.self) { settings.setupAssistantShown = $0 }

        return Result(
            settings: settings,
            resetFields: reset,
            droppedArchiveFolderCount: dropped,
            vaultRemovalPaused: removalPaused
        )
    }

    /// Engages the emergency stop and the keep-a-copy rule: no archiving or
    /// removal runs until the user reviews Project Vault settings.
    static func pausedVault(_ vault: VaultSettings) -> VaultSettings {
        var vault = vault
        vault.automationEmergencyStop = true
        vault.automaticArchiving = false
        vault.setSpaceIntent(.keepCopy)
        return vault
    }

    /// Keeps each Project Vault sub-field that decodes. RULE: salvage never
    /// increases destructive permission. Each unreadable field takes its
    /// least destructive value:
    ///
    /// | field                         | unreadable becomes                          |
    /// |-------------------------------|---------------------------------------------|
    /// | isEnabled                     | false (vault off)                           |
    /// | activeRootID / archiveRootID  | nil (no transfers without a root)           |
    /// | automaticArchiving            | false                                       |
    /// | rolloutStage                  | disabled                                    |
    /// | spaceIntent                   | keepCopy, legacy rollout stepped back       |
    /// | automationEmergencyStop       | true (stop engaged)                         |
    /// | independentBackupConfirmed    | false                                       |
    /// | keepLocalProjectIDs           | readable pins kept + removal paused         |
    /// | inactivity / free-space / retention days, launchAtLogin, dates |
    /// |                               | defaults; inert because automatic archiving |
    /// |                               | is always off after any vault reset          |
    static func salvageVault(
        _ object: [String: Any]
    ) -> (vault: VaultSettings, resetFields: [String], removalPaused: Bool) {
        var vault = VaultSettings()
        var reset: [String] = []

        func field<T: Decodable>(_ key: String, _ label: String, _ type: T.Type, _ apply: (T) -> Void) {
            guard let raw = object[key] else { return }
            if let value = decode(type, from: raw) {
                apply(value)
            } else {
                reset.append(label)
            }
        }

        /// Optional fields: missing and explicit null both mean "not set".
        func optionalField<T: Decodable>(_ key: String, _ label: String, _ type: T.Type, _ apply: (T?) -> Void) {
            guard let raw = object[key] else { return }
            if raw is NSNull {
                apply(nil)
            } else if let value = decode(type, from: raw) {
                apply(value)
            } else {
                reset.append(label)
            }
        }

        field("isEnabled", "Project Vault on/off", Bool.self) { vault.isEnabled = $0 }
        optionalField("activeRootID", "Project Vault active folder", UUID.self) { vault.activeRootID = $0 }
        optionalField("archiveRootID", "Project Vault archive folder", UUID.self) { vault.archiveRootID = $0 }
        field("automaticArchiving", "automatic archiving", Bool.self) { vault.automaticArchiving = $0 }
        field("inactivityDays", "Project Vault inactivity days", Int.self) { vault.inactivityDays = $0 }
        field("minimumFreeSpaceGiB", "Project Vault free-space threshold", Int.self) {
            vault.minimumFreeSpaceGiB = $0
        }
        field("transferFreeSpaceReserveGiB", "Project Vault free-space reserve", Int.self) {
            vault.transferFreeSpaceReserveGiB = $0
        }
        field("keepPreviousGenerationDays", "Project Vault previous-copy days", Int.self) {
            vault.keepPreviousGenerationDays = $0
        }
        field("launchAtLogin", "Project Vault launch at login", Bool.self) { vault.launchAtLogin = $0 }
        field("rolloutStage", "Project Vault mode", VaultSettings.RolloutStage.self) { vault.rolloutStage = $0 }

        if let rawIntent = object["spaceIntent"] {
            if let intent = decode(VaultSettings.SpaceIntent.self, from: rawIntent) {
                vault.spaceIntent = intent
            } else {
                reset.append("Project Vault free-space rule")
                // Safe default, and step a legacy removal rollout back so the
                // pair cannot still read as removal permission.
                vault.setSpaceIntent(.keepCopy)
            }
        } else {
            vault.spaceIntent = VaultSettings.migratedIntent(from: vault.rolloutStage)
        }

        if let rawStop = object["automationEmergencyStop"] {
            if let stop = decode(Bool.self, from: rawStop) {
                vault.automationEmergencyStop = stop
            } else {
                // A stuck stop must never be switched off by a repair.
                vault.automationEmergencyStop = true
                reset.append("Project Vault emergency stop (turned on)")
            }
        }
        field("independentBackupConfirmed", "Project Vault backup confirmation", Bool.self) {
            vault.independentBackupConfirmed = $0
        }
        optionalField("lastSuccessfulVerificationAt", "Project Vault last check date", Date.self) {
            vault.lastSuccessfulVerificationAt = $0
        }
        optionalField("lastRestoreDrillAt", "Project Vault last restore test date", Date.self) {
            vault.lastRestoreDrillAt = $0
        }
        var removalPaused = false
        if let rawKeepLocal = object["keepLocalProjectIDs"] {
            let entries = rawKeepLocal as? [Any]
            let ids = entries?.compactMap { $0 as? String } ?? []
            if entries == nil || ids.count != entries?.count {
                // Unpinning a Keep Local project would expose it to removal.
                // Keep every readable pin, and pause removal until the user
                // reviews the list (the raw value stays in the backup).
                vault.keepLocalProjectIDs = Set(ids)
                removalPaused = true
            } else {
                vault.keepLocalProjectIDs = Set(ids)
            }
        }

        if removalPaused {
            let wasArchivingAutomatically = vault.automaticArchiving
            vault = pausedVault(vault)
            if wasArchivingAutomatically, !reset.contains("automatic archiving") {
                reset.append("automatic archiving")
            }
        }
        if (!reset.isEmpty || removalPaused), vault.automaticArchiving {
            vault.automaticArchiving = false
            if !reset.contains("automatic archiving") {
                reset.append("automatic archiving")
            }
        }
        return (vault, reset, removalPaused)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from raw: Any) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Writes the raw settings blob next to the app's other support files and
/// proves it landed before any repair is allowed to proceed.
enum SettingsBackupWriter {
    static func write(_ data: Data, to directory: URL, now: Date, fileManager: FileManager = .default) throws -> URL {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            let stamp = formatter.string(from: now)
            var url = directory.appendingPathComponent("settings-\(stamp).json", isDirectory: false)
            var suffix = 2
            while fileManager.fileExists(atPath: url.path) {
                url = directory.appendingPathComponent("settings-\(stamp)-\(suffix).json", isDirectory: false)
                suffix += 1
            }
            try data.write(to: url, options: [.withoutOverwriting])
            guard try Data(contentsOf: url) == data else {
                throw SettingsRepairError.backupFailed
            }
            return url
        } catch {
            throw SettingsRepairError.backupFailed
        }
    }
}

/// Observable repair state shared by the main-window notice and the Settings
/// banner. Mutations happen on the main actor; construction is nonisolated so
/// `ToolContext` can create a default one (like `AppSettingsObserver`).
public final class SettingsRepairModel: ObservableObject, @unchecked Sendable {
    public static let pausedMessage = "Some settings couldn't be read, so changes are paused to protect them."
    public static let backupFailedMessage = "The backup couldn't be saved, so nothing was changed."
    public static let repairFailedMessage = "Settings couldn't be repaired, so nothing was changed."

    @Published public private(set) var needsRepair: Bool
    @Published public private(set) var resultMessage: String?
    @Published public private(set) var errorMessage: String?

    private let repairer: (any SettingsRepairing)?
    private let backupDirectory: URL?
    private let diagnostics: (any Diagnostics)?
    private var repairHandlers: [@MainActor () -> Void] = []

    public init(store: any SettingsStore, backupDirectory: URL?, diagnostics: (any Diagnostics)? = nil) {
        let repairer = store as? any SettingsRepairing
        self.repairer = repairer
        self.backupDirectory = backupDirectory
        self.diagnostics = diagnostics
        self.needsRepair = repairer?.storedSettingsNeedRepair() ?? false
    }

    /// Runs after every successful repair so mounted consumers reload what
    /// they could not read before (archive roots, appearance, menu bar icon).
    @MainActor
    public func addRepairHandler(_ handler: @escaping @MainActor () -> Void) {
        repairHandlers.append(handler)
    }

    @MainActor
    public func refresh() {
        let needs = repairer?.storedSettingsNeedRepair() ?? false
        if needs != needsRepair { needsRepair = needs }
    }

    /// Explicit user action only. The normal load path never repairs.
    @MainActor
    @discardableResult
    public func repair() -> Bool {
        guard let repairer else { return false }
        guard let backupDirectory else {
            errorMessage = Self.backupFailedMessage
            return false
        }
        do {
            guard let outcome = try repairer.repairStoredSettings(backupDirectory: backupDirectory, now: Date()) else {
                needsRepair = false
                errorMessage = nil
                return true
            }
            diagnostics?.log(
                .info,
                "Settings repaired; reset=\(outcome.resetFields) dropped=\(outcome.droppedArchiveFolderCount) backup=\(outcome.backupURL.path)"
            )
            needsRepair = false
            errorMessage = nil
            resultMessage = outcome.message
            for handler in repairHandlers { handler() }
            return true
        } catch SettingsRepairError.backupFailed {
            diagnostics?.log(.error, "Settings repair stopped: backup could not be written to \(backupDirectory.path)")
            errorMessage = Self.backupFailedMessage
            return false
        } catch {
            diagnostics?.log(.error, "Settings repair failed: \(error)")
            errorMessage = Self.repairFailedMessage
            refresh()
            return false
        }
    }

    @MainActor
    public func dismissResult() {
        resultMessage = nil
    }
}
