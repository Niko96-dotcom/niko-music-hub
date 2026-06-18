import AppCore
import NikoMusicCore
import SwiftUI

extension ProjectWorkflowStatus {
    var archiveSymbolName: String {
        switch self {
        case .songstarterBeat: "sparkles"
        case .song: "music.note"
        case .sessionProd: "person.2"
        case .prod: "slider.horizontal.3"
        case .waitingFeedback: "hourglass"
        case .feedbackTodo: "checklist"
        case .done: "checkmark.seal"
        }
    }

    var archiveTint: Color {
        switch self {
        case .songstarterBeat: .mint
        case .song: .cyan
        case .sessionProd: .indigo
        case .prod: .orange
        case .waitingFeedback: .yellow
        case .feedbackTodo: .pink
        case .done: HubDesignSystem.Colors.success
        }
    }
}

struct ArchiveWorkflowStatusPill: View {
    let status: ProjectWorkflowStatus?
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status?.archiveSymbolName ?? "tag")
                .font(.system(size: compact ? 8 : 10, weight: .semibold))
            Text(status?.shortTitle ?? "No Status")
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 18 : 22)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(stroke)
        )
        .help(status?.displayTitle ?? "No status")
        .accessibilityLabel(status?.displayTitle ?? "No status")
    }

    private var foreground: Color {
        status?.archiveTint ?? .secondary
    }

    private var fill: Color {
        (status?.archiveTint ?? Color.primary).opacity(status == nil ? 0.06 : 0.14)
    }

    private var stroke: Color {
        (status?.archiveTint ?? Color.primary).opacity(status == nil ? 0.12 : 0.24)
    }
}
