import Foundation
import SwiftUI

/// Pure Tools-menu ordering and ⌘1…⌘9 assignment from `ToolRegistry.metadata`.
///
/// Sidebar / menu order is Library (Archive Browser), then production tools in
/// registry order, then Settings last. Settings never gets a digit (use ⌘,).
/// Archive Browser is ⌘1 when present; the next eight production tools take
/// ⌘2…⌘9; further production tools have no digit shortcut.
public enum HubToolsShortcutMap {
    public static let archiveToolID = ToolFeatureID("archive-browser")
    public static let settingsToolID = ToolFeatureID("settings")

    /// Same grouping as `ToolSidebarView`: Archive, production, Settings last.
    public static func menuMetadata(from metadata: [ToolMetadata]) -> [ToolMetadata] {
        let archive = metadata.filter { $0.id == archiveToolID }
        let production = metadata.filter { $0.id != archiveToolID && $0.id != settingsToolID }
        let settings = metadata.filter { $0.id == settingsToolID }
        return archive + production + settings
    }

    /// Command-digit character `"1"`…`"9"` for a tool in sidebar order, or `nil`.
    public static func commandDigit(for id: ToolFeatureID, in metadata: [ToolMetadata]) -> Character? {
        guard id != settingsToolID else { return nil }
        let switchable = menuMetadata(from: metadata).filter { $0.id != settingsToolID }
        guard let index = switchable.firstIndex(where: { $0.id == id }), index < 9 else {
            return nil
        }
        return Character(String(index + 1))
    }

    /// `KeyEquivalent` for the Tools-menu command-digit shortcut, if any.
    public static func keyEquivalent(for id: ToolFeatureID, in metadata: [ToolMetadata]) -> KeyEquivalent? {
        commandDigit(for: id, in: metadata).map { KeyEquivalent($0) }
    }
}
