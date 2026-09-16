import AppCore
import SwiftUI

enum ArchiveKeyboardFocus: Hashable {
    case archive
    case search
}

/// Text entry changes much more frequently than the browse results. Own its
/// publication separately so a keystroke does not invalidate the whole archive.
@MainActor
final class ArchiveSearchInput: ObservableObject {
    @Published var query = ""
}

struct ArchiveSearchTextField: View {
    @ObservedObject var input: ArchiveSearchInput
    let onEdit: @MainActor @Sendable (String) -> Void
    var isDisabled: Bool = false
    @FocusState.Binding var keyboardFocus: ArchiveKeyboardFocus?

    var body: some View {
        HStack(spacing: 4) {
            TextField(
                "Search songs",
                text: Binding(
                    get: { input.query },
                    set: { onEdit($0) }
                ),
                prompt: Text("Search songs")
                    .foregroundColor(HubDesignSystem.Palette.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .focused($keyboardFocus, equals: .search)
            .disabled(isDisabled)
            .accessibilityHint(
                isDisabled
                    ? "Scan the archive first."
                    : "Filters the song list as you type."
            )
            .onKeyPress(.escape) {
                handleEscape()
                return .handled
            }

            if !input.query.isEmpty {
                HubIconButton(
                    systemImage: "xmark.circle.fill",
                    accessibilityLabel: "Clear search",
                    help: "Clear the search field"
                ) {
                    onEdit("")
                    keyboardFocus = .search
                }
            }
        }
    }

    private func handleEscape() {
        if input.query.isEmpty {
            ArchiveShortcutFocusPolicy.claimArchiveKeyFocus()
            keyboardFocus = .archive
        } else {
            onEdit("")
            keyboardFocus = .search
        }
    }
}
