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
    /// Request the Settings window Helpers pane from feature views that do not hold a router.
    static let hubOpenSettingsHelpers = Notification.Name("NikoMusicHub.hubOpenSettingsHelpers")
}

/// Deep link used by helper-missing recovery (NMH-010) and the health strip.
public enum HubSettingsHelpersAction {
    public static func openSettingsHelpers() {
        NotificationCenter.default.post(name: .hubOpenSettingsHelpers, object: HubSettingsPane.helpers)
    }
}
