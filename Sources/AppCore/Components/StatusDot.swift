import SwiftUI

public struct StatusDot: View {
    public let state: JobState

    public init(state: JobState) {
        self.state = state
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: HubDesignSystem.Size.statusDot, height: HubDesignSystem.Size.statusDot)
    }

    private var color: Color {
        switch state {
        case .queued:
            return .secondary
        case .running:
            return HubDesignSystem.Colors.accent
        case .completed:
            return HubDesignSystem.Colors.success
        case .failed:
            return HubDesignSystem.Colors.danger
        case .canceled:
            return HubDesignSystem.Colors.warning
        }
    }
}
