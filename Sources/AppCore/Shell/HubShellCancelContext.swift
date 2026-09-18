import SwiftUI

/// What the main window's Edit ▸ Cancel commands need from the shell: the
/// selected tool, published as a focused *scene* value so the items act only
/// while the main window is the key scene (not Settings or Help).
public struct HubShellCancelContext: Equatable, Sendable {
    public let selectedToolID: ToolFeatureID?

    public init(selectedToolID: ToolFeatureID?) {
        self.selectedToolID = selectedToolID
    }
}

private struct HubShellCancelContextKey: FocusedValueKey {
    typealias Value = HubShellCancelContext
}

public extension FocusedValues {
    var hubShellCancelContext: HubShellCancelContext? {
        get { self[HubShellCancelContextKey.self] }
        set { self[HubShellCancelContextKey.self] = newValue }
    }
}
