import AppCore
import Foundation
import NikoMusicCore

/// Archive-only Project Vault cards are restore targets, not workflow inputs.
/// Keeping this decision shared between card surfaces and the view model prevents
/// drag/drop or menu affordances from bypassing the same safety boundary.
enum ProjectVaultCardWorkflowPolicy {
    static func allowsWorkflowMutation(for presentation: ProjectVaultCardPresentation?) -> Bool {
        guard let presentation else { return true }
        switch presentation.state {
        case .active, .keepLocal:
            return true
        case .archived, .restoring, .archiving, .needsAttention:
            return false
        }
    }
}
