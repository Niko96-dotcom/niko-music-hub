import SwiftUI

public struct StatusDot: View {
    public let state: JobState

    public init(state: JobState) {
        self.state = state
    }

    public var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(color)
            .font(.system(size: HubDesignSystem.Size.statusDot))
            .frame(width: HubDesignSystem.Size.statusDot, height: HubDesignSystem.Size.statusDot)
            .accessibilityLabel(accessibilityText)
    }

    /// SF Symbol that distinguishes the state by shape so color is a secondary cue (NMH-079).
    public var symbolName: String {
        switch state {
        case .queued:
            return "circle"
        case .running:
            return "ellipsis.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .canceled:
            return "minus.circle"
        }
    }

    /// VoiceOver label when the dot is used without adjacent status text (NMH-079).
    public var accessibilityText: String {
        switch state {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .canceled:
            return "Canceled"
        }
    }

    private var color: Color {
        switch state {
        case .queued:
            return .secondary
        case .running:
            return HubDesignSystem.Colors.indicator
        case .completed:
            return HubDesignSystem.Colors.success
        case .failed:
            return HubDesignSystem.Colors.danger
        case .canceled:
            return HubDesignSystem.Colors.warning
        }
    }
}
