import AppCore
import SwiftUI

struct ArchiveFirstRunView: View {
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

            Text("Music archive")
                .font(HubDesignSystem.Typography.screenTitle())
                .multilineTextAlignment(.center)

            Text(
                "Choose the folder that holds your song projects. The hub scans read-only — files are never renamed or moved"
            )
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HubLabeledButton(
                icon: "folder.badge.plus",
                label: "Choose archive folder",
                style: .primary,
                help: "Choose your Cubase or Ableton projects folder"
            ) {
                onChooseRoot()
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .hubSurface(.card, cornerRadius: HubDesignSystem.Radius.popover)
        .shadow(color: HubDesignSystem.Elevation.high.color, radius: HubDesignSystem.Elevation.high.radius, y: HubDesignSystem.Elevation.high.y)
    }
}
