import SwiftUI

public struct OutputRow: View {
    public let sourceName: String
    public let outputName: String?
    public let state: JobState
    public let statusText: String
    public let progress: Double?
    public let onReveal: (() -> Void)?
    public let onRetry: (() -> Void)?

    public init(
        sourceName: String,
        outputName: String? = nil,
        state: JobState,
        statusText: String,
        progress: Double? = nil,
        onReveal: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.sourceName = sourceName
        self.outputName = outputName
        self.state = state
        self.statusText = statusText
        self.progress = progress
        self.onReveal = onReveal
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: 12) {
            StatusDot(state: state)

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceName)
                    .font(.system(size: 13, weight: .semibold))
                if let outputName = outputName {
                    Text(outputName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if let progress = progress, state == .running {
                ProgressView(value: progress)
                    .frame(width: 80)
            }

            if state == .failed, let onRetry = onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }

            if (state == .completed || state == .queued) && onReveal != nil {
                Button("Reveal", action: onReveal!)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private var statusColor: Color {
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