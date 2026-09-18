/// Keeps the interaction contract testable without making a gesture recognizer
/// wait on another recognizer's failure. The single-click gesture owns preview
/// selection; the simultaneous double-click gesture owns detail navigation.
enum ArchiveBoardCardInteractionPolicy {
    enum Activation: Equatable {
        case singleClick
        case doubleClick
        case accessibilityDefault
        case accessibilityOpenDetail
    }

    enum Action: Equatable {
        case select
        case openDetail
    }

    static func action(for activation: Activation) -> Action {
        switch activation {
        case .singleClick, .accessibilityDefault:
            .select
        case .doubleClick, .accessibilityOpenDetail:
            .openDetail
        }
    }
}
