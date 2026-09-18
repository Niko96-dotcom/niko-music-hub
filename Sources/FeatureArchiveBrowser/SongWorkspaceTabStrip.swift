import AppCore
import SwiftUI

/// Underlined tab strip above the song workspace content.
struct SongWorkspaceTabStrip: View {
    @Binding var selection: SongWorkspaceTab

    var body: some View {
        HStack(spacing: 22) {
            ForEach(SongWorkspaceTab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .font(HubDesignSystem.Typography.bodySmall().weight(selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary)
                        .padding(.bottom, 12)
                        .overlay(alignment: .bottom) {
                            if selection == tab { Rectangle().frame(height: 2) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Divider() }
    }
}
