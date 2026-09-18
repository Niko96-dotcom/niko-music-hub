import Foundation

/// Identity of the single main window (`Window(id: "main")`), shared by the
/// chrome configurator, window-scoped key handling, and `openWindow(id:)`.
public enum HubMainWindowIdentity {
    /// `NSWindow.identifier` raw value set by the chrome configurator.
    public static let identifierRawValue = "hub.main"
    /// SwiftUI scene id used with `openWindow(id:)`.
    public static let sceneID = "main"
}
