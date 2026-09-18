import AppCore
import NikoMusicCore
import SwiftUI

/// Collaborator checkboxes for one song. The address book itself is edited
/// from the sidebar.
struct SongCollaboratorsSection: View {
    let collaborators: [Collaborator]
    let selectedIDs: [String]
    let onToggle: (Collaborator, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HubSectionHeader("Collaborators")

            if collaborators.isEmpty {
                Text("Add collaborators under Library → Collaborators in the sidebar.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            } else {
                ForEach(collaborators) { collaborator in
                    Toggle(collaborator.displayName, isOn: Binding(
                        get: { selectedIDs.contains(collaborator.id) },
                        set: { onToggle(collaborator, $0) }
                    ))
                }
            }
        }
    }
}
