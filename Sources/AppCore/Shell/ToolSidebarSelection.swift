import SwiftUI

/// Sidebar tool selection for VoiceOver and arrow-key movement.
///
/// Helper Tools is not in `ToolRegistry.metadata`, so it never becomes selected.
public enum ToolSidebarSelection {
    public static func accessibilityValue(isSelected: Bool) -> String {
        isSelected ? "Selected" : ""
    }

    public static func accessibilityTraits(isSelected: Bool) -> AccessibilityTraits {
        isSelected ? .isSelected : []
    }

    /// Cycles `registry.metadata` (every registered tool, including Settings).
    public static func move(
        direction: MoveCommandDirection,
        metadata: [ToolMetadata],
        selectedID: ToolFeatureID?
    ) -> ToolFeatureID? {
        let ids = metadata.map(\.id)
        guard !ids.isEmpty else { return nil }
        guard let selectedID, let index = ids.firstIndex(of: selectedID) else {
            return (direction == .up || direction == .left) ? ids.last : ids.first
        }
        switch direction {
        case .down, .right:
            return ids[(index + 1) % ids.count]
        case .up, .left:
            return ids[(index - 1 + ids.count) % ids.count]
        @unknown default:
            return selectedID
        }
    }
}
