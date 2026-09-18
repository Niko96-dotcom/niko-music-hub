import AppCore
import NikoMusicCore
import SwiftUI

/// One project file in the Versions tab with its per-version actions menu.
struct SongProjectVersionRow: View {
    let version: ProjectVersion
    let isMain: Bool
    let isIgnored: Bool
    let openBlockReason: String?
    let onOpen: () -> Void
    let onSetMain: () -> Void
    let onHide: () -> Void

    private var metaLine: String? {
        var parts: [String] = []
        if let versionNumber = version.detectedVersionNumber {
            parts.append("v\(versionNumber)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(version.fileName)
                    .font(HubDesignSystem.Typography.bodySmall().weight(isMain ? .semibold : .regular))
                    .foregroundStyle(isIgnored ? HubDesignSystem.Palette.textTertiary : HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(version.filePath.path)
                if isMain {
                    Text("Main")
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.accent)
                }
                if isIgnored {
                    Text("Hidden")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
                Spacer(minLength: 0)
                if !isIgnored {
                    Menu {
                        Button("Open in \(version.applicationName)", action: onOpen)
                            .disabled(openBlockReason != nil)
                            .help(openBlockReason ?? "Open this version in \(version.applicationName)")
                        Button("Set Main", action: onSetMain)
                            .disabled(isMain)
                        Button("Hide from browse", action: onHide)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Actions for \(version.fileName)")
                }
            }

            Text("\(version.applicationName) · \(version.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)

            if let meta = metaLine {
                Text(meta)
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            }

        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HubDesignSystem.Palette.separator.opacity(0.55))
                .frame(height: 1)
        }
    }
}
