import SwiftUI

/// Whether the enclosing tool pane is the one the shell currently shows.
///
/// The shell keeps visited panes mounted (visibility flip, not rebuild), so a
/// pane cannot use `onAppear` / `onDisappear` to learn when it is active.
/// Tools read this to scope app-wide side effects — focused command values,
/// key monitors — to the visible pane only.
private struct HubToolIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var hubToolIsActive: Bool {
        get { self[HubToolIsActiveKey.self] }
        set { self[HubToolIsActiveKey.self] = newValue }
    }
}
