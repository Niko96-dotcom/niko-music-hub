import AppCore
import NikoMusicCore
import SwiftUI

/// A stable image for the native drag session. It has no hover state, buttons,
/// or observed model, so the lifted card doesn't capture an in-flight hover
/// animation or change its contents while moving between stages.
struct ArchiveBoardDragPreview: View {
    let title: String
    let status: ProjectWorkflowStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .lineLimit(2)
            Text(status?.displayTitle ?? "No Status")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 184, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(HubDesignSystem.Palette.surfaceRaised)
        }
    }
}
