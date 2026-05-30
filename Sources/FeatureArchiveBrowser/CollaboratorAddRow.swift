import AppCore
import SwiftUI

/// Shared name field + add control for the collaborator address book.
struct CollaboratorAddRow: View {
    @Binding var draftName: String
    var placeholder: String = "Add name"
    var fieldFont: Font = .system(size: 11)
    var onAdd: (String) -> Bool

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(fieldFont)
            HubIconButton(
                systemImage: "person.badge.plus",
                accessibilityLabel: "Add collaborator",
                help: "Add collaborator to address book",
                isEnabled: !trimmedName.isEmpty
            ) {
                if onAdd(trimmedName) {
                    draftName = ""
                }
            }
        }
    }
}
