import AppCore

extension ToolSection {
    /// The section that the real tool with this ID declares, for test stubs that
    /// stand in for it (the Archive Browser in Library, Settings at the bottom).
    static func declared(by id: ToolFeatureID) -> ToolSection {
        switch id {
        case .archiveBrowser: .library
        case "settings": .settings
        default: .production
        }
    }
}
