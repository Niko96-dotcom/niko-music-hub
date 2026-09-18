import Foundation
import SwiftUI

/// One place the user has been: a tool, plus an opaque tool-owned route
/// (e.g. the archive's "board" / "detail:<songID>" / "list").
public struct HubNavigationEntry: Equatable, Sendable {
    public let toolID: ToolFeatureID
    public let route: String?

    public init(toolID: ToolFeatureID, route: String? = nil) {
        self.toolID = toolID
        self.route = route
    }
}

/// Browser-style back/forward stack for the shell.
///
/// The shell records tool switches; tools that have inner navigation
/// (the archive) record their own route changes and register a restorer
/// so a back/forward step can put them back where they were. Recording is
/// suppressed while a restore runs so the step itself does not append.
@MainActor
public final class HubNavigationHistory: ObservableObject {
    public static let maxEntries = 100

    @Published public private(set) var entries: [HubNavigationEntry] = []
    @Published public private(set) var index: Int = -1
    private var restorers: [ToolFeatureID: @MainActor (String?) -> Void] = [:]
    private var lastRoutes: [ToolFeatureID: String] = [:]
    private var isRestoring = false

    nonisolated public init() {}

    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index >= 0 && index < entries.count - 1 }
    public var current: HubNavigationEntry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    /// Last route a tool reported, so a plain tool switch lands on the
    /// tool's current page rather than its default.
    public func lastRoute(for toolID: ToolFeatureID) -> String? {
        lastRoutes[toolID]
    }

    /// Updates the tool's last-known route without adding an entry (used
    /// when a tool attaches, before the shell has recorded anything).
    public func noteRoute(toolID: ToolFeatureID, route: String) {
        lastRoutes[toolID] = route
    }

    public func registerRestorer(for toolID: ToolFeatureID, _ restore: @escaping @MainActor (String?) -> Void) {
        restorers[toolID] = restore
    }

    /// Appends an entry, dropping any forward history. Identical consecutive
    /// entries collapse; calls made during a restore are ignored.
    public func record(toolID: ToolFeatureID, route: String? = nil) {
        if let route { lastRoutes[toolID] = route }
        guard !isRestoring else { return }
        let entry = HubNavigationEntry(toolID: toolID, route: route ?? lastRoutes[toolID])
        if entry == current { return }
        if index < entries.count - 1 {
            entries.removeSubrange((index + 1)...)
        }
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        index = entries.count - 1
    }

    @discardableResult
    public func goBack() -> HubNavigationEntry? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    @discardableResult
    public func goForward() -> HubNavigationEntry? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }

    /// Runs the tool's restorer for `entry` with recording suppressed.
    /// The caller is responsible for making `entry.toolID` the active tool.
    public func restore(_ entry: HubNavigationEntry) {
        isRestoring = true
        defer { isRestoring = false }
        if let route = entry.route { lastRoutes[entry.toolID] = route }
        restorers[entry.toolID]?(entry.route)
    }

    /// Runs `body` without recording (for programmatic tool switches that
    /// are part of a restore).
    public func withoutRecording(_ body: () -> Void) {
        let previous = isRestoring
        isRestoring = true
        body()
        isRestoring = previous
    }
}
