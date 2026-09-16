import NikoMusicCore
import SwiftUI

/// Shared board/list/Song-menu workflow access (NMH-005).
/// Context menu titles match the list; VoiceOver actions use "Move to …" / "Clear Status".
public enum SongWorkflowActions {
    public static let clearStatusMenuTitle = "No Status"
    public static let clearStatusAccessibilityName = "Clear Status"
    public static let songMenuTitle = "Move to…"

    public static func moveAccessibilityName(for status: ProjectWorkflowStatus) -> String {
        "Move to \(status.displayTitle)"
    }

    public static var accessibilityActionNames: [String] {
        ProjectWorkflowStatus.allCases.map(moveAccessibilityName(for:)) + [clearStatusAccessibilityName]
    }
}

struct SongWorkflowContextMenu: View {
    let allowsMutation: Bool
    let onSelect: ((ProjectWorkflowStatus?) -> Void)?

    var body: some View {
        if allowsMutation, let onSelect {
            Button(SongWorkflowActions.clearStatusMenuTitle) { onSelect(nil) }
            ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                Button(status.displayTitle) { onSelect(status) }
            }
        }
    }
}

struct SongWorkflowAccessibilityActions: ViewModifier {
    let enabled: Bool
    let onSelect: (ProjectWorkflowStatus?) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named: SongWorkflowActions.moveAccessibilityName(for: .songstarterBeat)) {
                    onSelect(.songstarterBeat)
                }
                .accessibilityAction(named: SongWorkflowActions.moveAccessibilityName(for: .song)) {
                    onSelect(.song)
                }
                .accessibilityAction(named: SongWorkflowActions.moveAccessibilityName(for: .sessionProd)) {
                    onSelect(.sessionProd)
                }
                .accessibilityAction(named: SongWorkflowActions.moveAccessibilityName(for: .prod)) {
                    onSelect(.prod)
                }
                .accessibilityAction(named: SongWorkflowActions.moveAccessibilityName(for: .waitingFeedback)) {
                    onSelect(.waitingFeedback)
                }
                .accessibilityAction(named: SongWorkflowActions.moveAccessibilityName(for: .feedbackTodo)) {
                    onSelect(.feedbackTodo)
                }
                .accessibilityAction(named: SongWorkflowActions.moveAccessibilityName(for: .done)) {
                    onSelect(.done)
                }
                .accessibilityAction(named: SongWorkflowActions.clearStatusAccessibilityName) {
                    onSelect(nil)
                }
        } else {
            content
        }
    }
}
