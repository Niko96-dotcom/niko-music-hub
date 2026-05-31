import AppCore
import SwiftUI

struct ArchiveFirstRunView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let onChooseRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start with an archive root")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.primary)

            Text(
                "Choose the folder that contains your Cubase song/project folders. "
                    + "Niko Music Hub scans read-only — your song folders on disk are never renamed or moved."
            )
            .font(.system(size: 14))
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Active projects folder (required)", systemImage: "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("You can add more archive roots later from the sidebar.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }

            HubIconButton(
                systemImage: "folder.badge.plus",
                accessibilityLabel: "Add archive root",
                help: "Choose your Cubase projects folder",
                prominent: true,
                action: onChooseRoot
            )
                .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: 480, alignment: .leading)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.shell)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }
}
