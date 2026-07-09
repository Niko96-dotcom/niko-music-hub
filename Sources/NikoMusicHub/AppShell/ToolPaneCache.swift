import AppCore
import SwiftUI

/// Owns one built tool pane per visited `ToolFeatureID`.
///
/// Tab switches flip visibility over these cached panes instead of tearing down and
/// rebuilding feature view trees (Stem Separation / Downloader / Archive are expensive).
@MainActor
final class ToolPaneCache: ObservableObject {
    private let registry: ToolRegistry
    private let context: ToolContext

    /// Visit order — drives which panes stay mounted in the shell ZStack.
    @Published private(set) var mountedIDs: [ToolFeatureID] = []
    private var views: [ToolFeatureID: AnyView] = [:]

    init(registry: ToolRegistry, context: ToolContext, initialToolID: ToolFeatureID? = nil) {
        self.registry = registry
        self.context = context
        if let initialToolID {
            // Mount before first body paint so the default tool is never a blank frame.
            ensureMounted(initialToolID)
        }
    }

    func ensureMounted(_ id: ToolFeatureID) {
        guard views[id] == nil else { return }
        guard let feature = registry.feature(for: id) else { return }
        views[id] = feature.makeView(context: context)
        mountedIDs.append(id)
    }

    func view(for id: ToolFeatureID) -> AnyView? {
        views[id]
    }
}
