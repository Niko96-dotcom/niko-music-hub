import Foundation

/// Settings window panes. Identity lives in AppCore so tests and deep links
/// do not depend on the NikoMusicHub app target.
public enum HubSettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general, archive, vault, helpers, updates

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .archive: "Archive"
        case .vault: "Vault"
        case .helpers: "Helpers"
        case .updates: "Updates"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .archive: "music.note.house"
        case .vault: "archivebox"
        case .helpers: "wrench.and.screwdriver"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

public extension Notification.Name {
    static let hubOpenSettingsPane = Notification.Name("NikoMusicHub.hubOpenSettingsPane")
}
