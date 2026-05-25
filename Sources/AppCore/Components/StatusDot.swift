import SwiftUI

public struct StatusDot: View {
    public let state: JobState

    public init(state: JobState) {
        self.state = state
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .queued:
            return .secondary
        case .running:
            return .green
        case .completed:
            return .green
        case .failed:
            return .red
        case .canceled:
            return .orange
        }
    }
}