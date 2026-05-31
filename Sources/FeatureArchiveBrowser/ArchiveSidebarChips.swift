import AppCore
import SwiftUI

struct ArchiveShelfChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(
                    isSelected ? HubCompactChipColors.archive.selectedForeground : HubCompactChipColors.archive.unselectedForeground
                )
                .padding(.horizontal, 10)
                .frame(height: HubDesignSystem.Size.chipHeight)
                .background {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                        .fill(isSelected ? HubCompactChipColors.archive.selectedFill : HubCompactChipColors.archive.unselectedFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.chip, style: .continuous)
                        .strokeBorder(
                            isSelected ? HubCompactChipColors.archive.selectedStroke : HubCompactChipColors.archive.unselectedStroke,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
        }
        .buttonStyle(.plain)
    }
}
