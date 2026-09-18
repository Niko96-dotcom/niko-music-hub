import AppCore
import NikoMusicCore
import SwiftUI

/// Versions tab: every project file of the song with main/hidden state.
struct SongProjectVersionsSection: View {
    let song: Song
    let openBlockReason: String?
    let onOpen: (ProjectVersion) -> Void
    let onSetMain: (ProjectVersion) -> Void
    let onHide: (ProjectVersion) -> Void
    let onRevertToAuto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HStack(alignment: .firstTextBaseline) {
                HubSectionHeader("Project versions")
                Spacer()
                Text(song.cprSelectionMode == .manual ? "Manual main" : "Auto main")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

            if song.projectVersions.isEmpty {
                Text("No project files (.cpr or .als) found")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.warning)
            } else {
                if let reason = openBlockReason {
                    Text(reason)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Version archives can contain hundreds of CPRs. Build rows (and
                // read their file metadata) as they enter the detail viewport.
                LazyVStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                    ForEach(song.projectVersions, id: \.id) { version in
                        SongProjectVersionRow(
                            version: version,
                            isMain: song.effectiveLatestCPR?.id == version.id,
                            isIgnored: song.ignoredCPRVersionIDs.contains(version.id),
                            openBlockReason: openBlockReason,
                            onOpen: { onOpen(version) },
                            onSetMain: { onSetMain(version) },
                            onHide: { onHide(version) }
                        )
                    }
                }
                if song.cprSelectionMode == .manual {
                    HubLabeledButton(
                        icon: "arrow.uturn.backward",
                        label: "Revert to auto project",
                        style: .secondary,
                        help: "Revert to automatic project selection",
                        action: onRevertToAuto
                    )
                }
            }
        }
    }
}
