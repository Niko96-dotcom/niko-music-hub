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
    @FocusState.Binding var keyboardFocus: ArchiveKeyboardFocus?

    var body: some View {
        TextField("", text: Binding(
            get: { input.query },
            set: { value in onEdit(value) }
        ), prompt: Text("Search songs").foregroundColor(HubDesignSystem.Palette.textTertiary))
        .textFieldStyle(.plain)
        .font(HubDesignSystem.Typography.body())
        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
        .focused($keyboardFocus, equals: .search)
    }
}
