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

/// Compact status control for song rows — one plain button shows the real pill; a popover
/// handles selection so macOS menu label styling cannot duplicate or flatten the chip.
struct ArchiveWorkflowStatusMenu: View {
    let status: ProjectWorkflowStatus?
    var compact = false
    let onSelect: (ProjectWorkflowStatus?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            statusLabel
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            pickerContent
                .frame(minWidth: 188)
        }
        .fixedSize()
        .help("Change workflow status")
        .accessibilityLabel("Workflow status")
        .accessibilityValue(status?.displayTitle ?? "No status")
        .accessibilityHint("Opens menu to change workflow status")
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let status {
            ArchiveWorkflowStatusPill(status: status, compact: compact)
        } else {
            Text("No Status")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
    }

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            pickerRow(nil, title: "No Status", icon: "tag")
            ForEach(ProjectWorkflowStatus.allCases, id: \.self) { option in
                pickerRow(option, title: option.displayTitle, icon: option.archiveSymbolName)
            }
        }
        .padding(.vertical, 6)
    }

    private func pickerRow(_ value: ProjectWorkflowStatus?, title: String, icon: String) -> some View {
        Button {
            onSelect(value)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Group {
                    if status == value {
                        Image(systemName: "checkmark")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 10)

                Label(title, systemImage: icon)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
