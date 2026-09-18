import AppCore
import SwiftUI

/// Same quiet inset search style as the sidebar — the sidebar is hidden
/// while the board owns the page, so search must live here too.
struct ArchiveBoardSearchField: View {
    let input: ArchiveSearchInput
    let onEdit: @MainActor @Sendable (String) -> Void
    let isDisabled: Bool
    @FocusState.Binding var keyboardFocus: ArchiveKeyboardFocus?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            ArchiveSearchTextField(
                input: input,
                onEdit: onEdit,
                isDisabled: isDisabled,
                keyboardFocus: $keyboardFocus
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
    }
}
