import AppCore
import SwiftUI

/// Owns one built tool pane per visited `ToolFeatureID`.
///
/// Tab switches flip visibility over these cached panes instead of tearing down and
/// rebuilding feature view trees (Stem Separation / Downloader / Archive are expensive).
///
/// Not observable on purpose: the shell already re-renders when the session's
/// selected tool changes, and `mountOrder(selecting:)` lets the ZStack include a
/// newly selected pane in the same render pass (built lazily by `ensureMounted`),
/// so there is never a frame with no pane.
@MainActor
final class ToolPaneCache {
    private let registry: ToolRegistry
    private let context: ToolContext

    /// Visit order — drives which panes stay mounted in the shell ZStack.
    private(set) var mountedIDs: [ToolFeatureID] = []
    private var views: [ToolFeatureID: AnyView] = [:]

    init(registry: ToolRegistry, context: ToolContext) {
        self.registry = registry
        self.context = context
    }

    /// Mounted ids plus `selected` (appended when not yet visited).
    func mountOrder(selecting selected: ToolFeatureID?) -> [ToolFeatureID] {
        guard let selected, !mountedIDs.contains(selected), registry.feature(for: selected) != nil else {
            return mountedIDs
        }
        return mountedIDs + [selected]
    }

    /// Build the pane on first request; later requests return the cached view.
    @discardableResult
    func ensureMounted(_ id: ToolFeatureID) -> AnyView? {
        if let view = views[id] { return view }
        guard let feature = registry.feature(for: id) else { return nil }
        let view = feature.makeView(context: context)
        views[id] = view
        mountedIDs.append(id)
        return view
    }
}
