import Foundation

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

public struct AppSettings: Equatable, Codable, Sendable {
    public var outputFolder: StoredFolderLocation
    public var audioPreset: AudioPreset
    public var helperTools: HelperToolSettings
    public var maxRecordingDurationMinutes: Int
    public var archiveRoots: [StoredArchiveRoot]
    public var appearance: AppAppearance
    /// User completed first-run archive root onboarding (SPEC §5).
    public var archiveOnboardingCompleted: Bool
    /// Comma-separated folder-name terms to skip during archive scan (e.g. backup, tmp).
    public var scanExclusionTerms: String

    private enum CodingKeys: String, CodingKey {
        case outputFolder
        case audioPreset
        case helperTools
        case maxRecordingDurationMinutes
        case archiveRoots
        case appearance
        case archiveOnboardingCompleted
        case scanExclusionTerms
    }

    public init(
        outputFolder: StoredFolderLocation = StoredFolderLocation(),
        audioPreset: AudioPreset = .cubaseDefault,
        helperTools: HelperToolSettings = HelperToolSettings(),
        maxRecordingDurationMinutes: Int = 30,
        archiveRoots: [StoredArchiveRoot] = [],
        appearance: AppAppearance = .followSystem,
        archiveOnboardingCompleted: Bool = false,
        scanExclusionTerms: String = ""
    ) {
        self.outputFolder = outputFolder
        self.audioPreset = audioPreset
        self.helperTools = helperTools
        self.maxRecordingDurationMinutes = maxRecordingDurationMinutes
        self.archiveRoots = archiveRoots
        self.appearance = appearance
        self.archiveOnboardingCompleted = archiveOnboardingCompleted
        self.scanExclusionTerms = scanExclusionTerms
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        outputFolder = (try? container.decodeIfPresent(StoredFolderLocation.self, forKey: .outputFolder)) ?? StoredFolderLocation()
        audioPreset = (try? container.decodeIfPresent(AudioPreset.self, forKey: .audioPreset)) ?? .cubaseDefault
        helperTools = (try? container.decodeIfPresent(HelperToolSettings.self, forKey: .helperTools)) ?? HelperToolSettings()
        maxRecordingDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .maxRecordingDurationMinutes)) ?? 30
        archiveRoots = (try? container.decodeIfPresent([StoredArchiveRoot].self, forKey: .archiveRoots)) ?? []
        appearance = (try? container.decodeIfPresent(AppAppearance.self, forKey: .appearance)) ?? .followSystem
        archiveOnboardingCompleted = (try? container.decodeIfPresent(Bool.self, forKey: .archiveOnboardingCompleted)) ?? false
        scanExclusionTerms = (try? container.decodeIfPresent(String.self, forKey: .scanExclusionTerms)) ?? ""
    }

    public static let `default` = AppSettings()
}
