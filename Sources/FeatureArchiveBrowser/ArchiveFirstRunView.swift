import AppCore
import SwiftUI

struct ArchiveFirstRunView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let onChooseRoot: () -> Void

    var body: some View {
        VStack(spacing: HubDesignSystem.Spacing.panel) {
            Image(systemName: "music.note.house")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [HubDesignSystem.Colors.accent, HubDesignSystem.Colors.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to your Cubase archive")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(
                "Choose the folder that contains your song projects. The hub scans read-only — your files on disk are never renamed or moved."
            )
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HubLabeledButton(
                icon: "folder.badge.plus",
                label: "Choose Folder",
                style: .primary,
                help: "Choose your Cubase projects folder"
            ) {
                onChooseRoot()
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .hubGlassCard(cornerRadius: HubDesignSystem.Radius.shell)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }
}
