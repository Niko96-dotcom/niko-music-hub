import Foundation

/// Pure stateless filter: given the static allowlist and a live ToolRegistry,
/// returns only the entries the app can currently service.
/// - `.openTool(id)` entries are kept only when `registry.feature(for: id) != nil`.
/// - `.openApp` and `.revealOutputInbox` always pass through (MBAR-04).
public enum QuickAccessResolver {
    public static func resolve(
        entries: [QuickAccessEntry],
        registry: ToolRegistry
    ) -> [QuickAccessEntry] {
        entries.filter { entry in
            switch entry.command {
            case .openTool(let id):
                return registry.feature(for: id) != nil
            case .openApp, .revealOutputInbox, .restoreProject:
                return true
            }
        }
    }
}
