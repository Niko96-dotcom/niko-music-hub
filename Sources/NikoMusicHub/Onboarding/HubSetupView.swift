import AppCore
import FeatureArchiveBrowser
import SwiftUI

/// One-click helper-tool Set Up sheet. The model outlives the sheet so closing
/// never cancels an install.
struct HubSetupView: View {
    @ObservedObject var model: HelperToolSetupModel
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    let chooseArchiveFolder: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set Up Niko Music Hub")
                .font(HubDesignSystem.Typography.screenTitle())

            Text("The app downloads the free tools it needs into its own folder. Nothing else on your Mac changes.")
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                setupRow(
                    icon: "arrow.down.circle",
                    title: HelperToolBundle.downloadAndConvert.title,
                    detail: HelperToolBundle.downloadAndConvert.detail,
                    trailing: AnyView(bundleTrailing(.downloadAndConvert))
                )
                HubDesignSystem.Palette.separator
                    .frame(height: 1)
                setupRow(
                    icon: "waveform.path",
                    title: HelperToolBundle.stemSeparation.title,
                    detail: HelperToolBundle.stemSeparation.detail,
                    trailing: AnyView(bundleTrailing(.stemSeparation))
                )
                HubDesignSystem.Palette.separator
                    .frame(height: 1)
                setupRow(
                    icon: "folder",
                    title: "Music Archive",
                    detail: archiveDetail,
                    trailing: AnyView(archiveTrailing)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubSurface(.panel, state: .normal, cornerRadius: HubDesignSystem.Radius.popover)

            HStack {
                Spacer()
                HubLabeledButton(
                    icon: "xmark",
                    label: model.allInstalled ? "Done" : (model.isInstalling ? "Close" : "Later"),
                    style: .ghost
                ) {
                    onClose()
                }
                if !model.allInstalled {
                    HubLabeledButton(
                        icon: "arrow.down.circle",
                        label: "Install All",
                        style: .primary,
                        isEnabled: !model.isInstalling
                    ) {
                        model.installMissing()
                    }
                }
            }
        }
        .frame(width: 560)
        .padding(28)
        .onAppear { model.refresh() }
        .accessibilityIdentifier("hub_setup_sheet")
    }

    private var archiveDetail: String {
        if archiveViewModel.roots.isEmpty {
            return "Your Cubase or Ableton projects folder · optional"
        }
        return archiveViewModel.roots[0].lastPathComponent
    }

    private func setupRow(icon: String, title: String, detail: String, trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 15, weight: .light))
                .frame(width: 18, height: 18)
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                Text(detail)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
                .frame(width: 200, alignment: .trailing)
        }
        .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bundleTrailing(_ bundle: HelperToolBundle) -> some View {
        switch model.states[bundle] ?? .checking {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .notInstalled:
            HubLabeledButton(
                icon: "arrow.down.circle",
                label: "Install",
                style: .secondary,
                // One install at a time; a second click would be ignored.
                isEnabled: !model.isInstalling
            ) {
                model.install(bundle)
            }
        case .installing(let progress):
            VStack(alignment: .trailing, spacing: 6) {
                Group {
                    if let fraction = progress.fractionCompleted, fraction > 0 {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .tint(HubDesignSystem.Colors.indicator)
                Text(progress.phase)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .installed:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                .foregroundStyle(HubDesignSystem.Colors.success)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 6) {
                Text(message)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Colors.danger)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                HubLabeledButton(
                    icon: "arrow.clockwise",
                    label: "Try Again",
                    style: .secondary,
                    isEnabled: !model.isInstalling
                ) {
                    model.install(bundle)
                }
            }
        }
    }

    @ViewBuilder
    private var archiveTrailing: some View {
        if archiveViewModel.roots.isEmpty {
            HubLabeledButton(
                icon: "folder.badge.plus",
                label: "Choose Folder",
                style: .secondary
            ) {
                chooseArchiveFolder()
            }
        } else {
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                .foregroundStyle(HubDesignSystem.Colors.success)
        }
    }
}
