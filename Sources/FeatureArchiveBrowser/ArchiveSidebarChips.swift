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
                .padding(.horizontal, 10)
                .frame(height: HubDesignSystem.Size.chipHeight)
                .hubGlassChip(isSelected: isSelected, colors: .archive)
        }
        .buttonStyle(.plain)
    }
}
