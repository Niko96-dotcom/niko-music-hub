import Combine
import Foundation

/// The one shell flag the `App` scene graph observes: whether the
/// `MenuBarExtra(isInserted:)` scene is inserted.
///
/// Kept apart from `HubShellSession` on purpose. The App body re-evaluates
/// every scene on any publish of an object it observes, so the App must only
/// observe state that actually changes scene structure. Panel visibility and
/// the selected tool stay on `HubShellSession`, observed by the shell view and
/// the command groups that need them.
@MainActor
public final class MenuBarExtraState: ObservableObject {
    @Published public private(set) var isInserted: Bool

    public init(isInserted: Bool) {
        self.isInserted = isInserted
    }

    /// Publish only on change: the scene re-reads the binding on every pass.
    public func apply(_ inserted: Bool) {
        guard inserted != isInserted else { return }
        isInserted = inserted
    }
}
