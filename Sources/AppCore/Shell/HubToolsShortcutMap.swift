import Foundation
import SwiftUI

/// Pure Tools-menu ordering and ⌘1…⌘9 assignment from `ToolRegistry.metadata`.
///
/// The menu follows the sidebar (`ToolSection.sidebarOrder`): Library (Archive
/// Browser), then production tools in registry order, then Settings last. Settings
/// never gets a digit (use ⌘,). Archive Browser is ⌘1 when present; the next eight
/// production tools take ⌘2…⌘9; further production tools have no digit shortcut.
public enum HubToolsShortcutMap {
    public static func menuMetadata(from metadata: [ToolMetadata]) -> [ToolMetadata] {
        ToolSection.sidebarOrder(metadata)
    }

    /// Command-digit character `"1"`…`"9"` for a tool in sidebar order, or `nil`.
    public static func commandDigit(for id: ToolFeatureID, in metadata: [ToolMetadata]) -> Character? {
        let switchable = menuMetadata(from: metadata).filter { $0.section != .settings }
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
