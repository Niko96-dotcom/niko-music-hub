#if DEBUG
import AppCore
import FeatureAudioConverter
import Foundation

enum QuickAccessRoutingSmoke {
    @MainActor
    static func run() throws -> [String: String] {
        // Minimal registry with the asserted production tool
        let registry = try ToolRegistry(features: [AudioConverterFeature()])

        // Confirm resolver surfaces the wav-converter entry
        let entries = MenuBarMenuModel.resolvedEntries(registry: registry)
        guard !entries.isEmpty else {
            throw QuickAccessRoutingSmokeError("resolver returned no entries for wav-converter registry")
        }

        let router = QuickAccessRouter()

        // Assert openTool routing
        router.execute(.openTool("wav-converter"))
        guard router.selectedToolID?.rawValue == "wav-converter" else {
            throw QuickAccessRoutingSmokeError(
                "expected selectedToolID=wav-converter, got \(String(describing: router.selectedToolID))"
            )
        }

        // Assert revealOutputInbox routing
        router.execute(.revealOutputInbox)
        guard router.revealOutputInbox else {
            throw QuickAccessRoutingSmokeError("expected revealOutputInbox=true after execute(.revealOutputInbox)")
        }

        return [
            "quick_access_reveal_inbox": "\(router.revealOutputInbox)",
            "quick_access_routing": "select_tool_reveal_inbox",
            "quick_access_selected_tool": router.selectedToolID?.rawValue ?? "nil"
        ]
    }
}

private struct QuickAccessRoutingSmokeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
#endif
