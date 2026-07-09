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

/// Soft status chip (reference: `color.opacity(0.16)` fill + colored text, never a saturated
/// block, never a stroke). Status color only carries meaning when a real status is set — the
/// "No Status" case is rendered as quiet `textTertiary` text at the call site instead of this
/// pill (see `SongCardView`).
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
        .help(status?.displayTitle ?? "No status")
        .accessibilityLabel(status?.displayTitle ?? "No status")
    }

    private var foreground: Color {
        status?.archiveTint ?? HubDesignSystem.Palette.textSecondary
    }

    private var fill: Color {
        (status?.archiveTint ?? HubDesignSystem.Palette.textPrimary).opacity(status == nil ? 0.06 : 0.16)
    }
}

/// Compact status control for song rows — opens a menu on click without selecting the row.
struct ArchiveWorkflowStatusMenu: View {
    let status: ProjectWorkflowStatus?
    var compact = false
    let onSelect: (ProjectWorkflowStatus?) -> Void

    var body: some View {
        Picker(
            selection: Binding<ProjectWorkflowStatus?>(
                get: { status },
                set: { onSelect($0) }
            )
        ) {
            Text("No Status").tag(nil as ProjectWorkflowStatus?)
            ForEach(ProjectWorkflowStatus.allCases, id: \.self) { option in
                Label(option.displayTitle, systemImage: option.archiveSymbolName)
                    .tag(option as ProjectWorkflowStatus?)
            }
        } label: {
            Group {
                if let status {
                    ArchiveWorkflowStatusPill(status: status, compact: compact)
                } else {
                    Text("No Status")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change workflow status")
        .accessibilityLabel("Workflow status")
        .accessibilityValue(status?.displayTitle ?? "No status")
        .accessibilityHint("Opens menu to change workflow status")
    }
}
