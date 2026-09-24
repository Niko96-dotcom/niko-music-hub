import AppCore
import SwiftUI

struct ArchiveFirstRunView: View {
    let onChooseRoot: () -> Void
    let onSkip: () -> Void

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

            Text("Music archive")
                .font(HubDesignSystem.Typography.screenTitle())
                .multilineTextAlignment(.center)

            Text(
                "Pick the folder with your Cubase or Ableton songs. The app scans read-only — files are never renamed or moved."
            )
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HubLabeledButton(
                icon: "folder.badge.plus",
                label: "Choose Folder",
                style: .primary,
                help: "Choose your Cubase or Ableton projects folder"
            ) {
                onChooseRoot()
            }
            .controlSize(.large)

            HubLabeledButton(
                icon: "clock",
                label: "Not Now",
                style: .ghost
            ) {
                onSkip()
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .hubSurface(.card, cornerRadius: HubDesignSystem.Radius.popover)
        .shadow(color: HubDesignSystem.Elevation.high.color, radius: HubDesignSystem.Elevation.high.radius, y: HubDesignSystem.Elevation.high.y)
    }
}
