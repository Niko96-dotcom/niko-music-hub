import AppCore
import FeatureAudioConverter
import FeatureDownloader
import FeatureStemSeparation
import SwiftUI

struct HelperToolsHealthStrip: View {
    let context: ToolContext
    var onOpenSettingsHelpers: () -> Void = {
        HubSettingsHelpersAction.openSettingsHelpers()
    }

    @State private var snapshot = HelperToolsHealthStripModel.checking

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Helper Tools")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)

            ForEach(snapshot.items) { item in
                helperRow(item)
            }

            if snapshot.anyNeedsSetup {
                Text("Install missing helpers with Homebrew to enable downloader and conversion workflows.")
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HubLabeledButton(
                    icon: "wrench.and.screwdriver",
                    label: "Open Settings",
                    style: .secondary
                ) {
                    onOpenSettingsHelpers()
                }
            }
        }
        .padding(HubDesignSystem.Spacing.controlGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubSurface(.raised, state: stripState, cornerRadius: HubDesignSystem.Radius.popover)
        .task {
            await refresh()
        }
    }

    private func helperRow(_ item: HelperToolsHealthItem) -> some View {
        Button(action: onOpenSettingsHelpers) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color(for: item.state))
                    .frame(width: HubDesignSystem.Size.statusDot, height: HubDesignSystem.Size.statusDot)
                Text(item.label)
                    .font(HubDesignSystem.Typography.micro().weight(.medium))
                Spacer(minLength: 8)
                Text(item.state.displayText)
                    .font(HubDesignSystem.Typography.micro())
                    .foregroundStyle(color(for: item.state))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label) \(item.state.displayText)")
        .accessibilityHint("Opens Settings, Helpers pane.")
    }

    private var stripState: HubDesignSystem.ControlState {
        let states = snapshot.items.map(\.state)
        if states.contains(where: \.isError) {
            return .error
        }
        if states.contains(where: \.isWarning) {
            return .warning
        }
        return .normal
    }

    private func color(for state: HelperToolsHealthItem.State) -> Color {
        switch state {
        case .checking:
            return .secondary
        case .available:
            return HubDesignSystem.Colors.success
        case .missing, .unusable:
            return HubDesignSystem.Colors.danger
        case .outdated:
            return HubDesignSystem.Colors.warning
        }
    }

    private func refresh() async {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        let helperSettings = settings.helperTools

        let ytAvailability = await YtDlpHealthChecker().availability(settings: helperSettings)
        let ffmpegAvailability = await FFmpegHealthChecker().availability(settings: helperSettings)
        let demucsHealth = await DemucsMLXHealthChecker().availability(settings: helperSettings)

        snapshot = HelperToolsHealthStripModel.make(
            ytDlp: state(from: ytAvailability),
            ffmpeg: state(from: ffmpegAvailability),
            demucsMLX: state(from: demucsHealth)
        )
    }

    private func state(from availability: YtDlpAvailability) -> HelperToolsHealthItem.State {
        switch availability {
        case .missing:
            return .missing
        case .available(let version):
            return .available(version: version)
        case .outdated(let current, let minimum):
            return .outdated(current: current, minimum: minimum)
        case .unusable(let message):
            return .unusable(message: message)
        }
    }

    private func state(from availability: FFmpegAvailability) -> HelperToolsHealthItem.State {
        switch availability {
        case .missing:
            return .missing
        case .available(let version):
            return .available(version: version)
        case .unusable(let message):
            return .unusable(message: message)
        }
    }

    private func state(from health: StemBackendHealth) -> HelperToolsHealthItem.State {
        switch health {
        case .missing:
            return .missing
        case .ready(let version):
            return .available(version: version)
        case .unusable(let message):
            return .unusable(message: message)
        case .modelCacheMissing:
            return .unusable(message: "Model cache missing")
        }
    }
}
