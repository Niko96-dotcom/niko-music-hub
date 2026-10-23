import AppCore
import SwiftUI

struct HelperToolsHealthStrip: View {
    let context: ToolContext
    var onInstallTools: (() -> Void)?
    /// The app's one helper-status owner; this strip only shows it.
    @ObservedObject private var helperHealth: HelperToolHealth

    init(context: ToolContext, onInstallTools: (() -> Void)? = nil) {
        self.context = context
        self.onInstallTools = onInstallTools
        self.helperHealth = context.helperHealth
    }

    private func handleInstallTools() {
        if let onInstallTools {
            onInstallTools()
        } else {
            context.router.requestHelperToolSetup()
        }
    }

    private var snapshot: HelperToolsHealthStripModel {
        HelperToolsHealthStripModel.make(
            ytDlp: state(of: .ytDlp),
            ffmpeg: state(of: .ffmpeg),
            demucsMLX: state(of: .demucsMlx)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Helper Tools")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)

            ForEach(snapshot.items) { item in
                helperRow(item)
            }

            if snapshot.anyNeedsSetup {
                HubLabeledButton(
                    icon: "arrow.down.circle",
                    label: "Install Tools",
                    style: .primary
                ) {
                    handleInstallTools()
                }
            }
        }
        .padding(HubDesignSystem.Spacing.controlGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubSurface(.card, state: stripState, cornerRadius: HubDesignSystem.Radius.popover)
        .task {
            await refresh()
        }
    }

    private func helperRow(_ item: HelperToolsHealthItem) -> some View {
        Button(action: handleInstallTools) {
            HStack(spacing: 8) {
                Image(systemName: symbol(for: item.state))
                    .foregroundStyle(color(for: item.state))
                    .font(.system(size: HubDesignSystem.Size.statusDot))
                    .frame(width: HubDesignSystem.Size.statusDot, height: HubDesignSystem.Size.statusDot)
                    .accessibilityHidden(true)
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
        .accessibilityHint("Opens the helper setup sheet.")
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

    private func symbol(for state: HelperToolsHealthItem.State) -> String {
        switch state {
        case .checking:
            return "circle"
        case .available:
            return "checkmark.circle.fill"
        case .missing, .unusable:
            return "xmark.circle.fill"
        case .outdated:
            return "exclamationmark.circle"
        }
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

    /// Opening the popover probes every helper again, as before; the rows
    /// show the owner's answers as they arrive.
    private func refresh() async {
        for tool in [HelperTool.ytDlp, .ffmpeg, .demucsMlx] {
            await helperHealth.recheck(tool)
        }
    }

    private func state(of tool: HelperTool) -> HelperToolsHealthItem.State {
        switch helperHealth.statuses[tool] {
        case nil:
            return .checking
        case .missing:
            return .missing
        case .ready(let version):
            return .available(version: version)
        case .outdated(let current, let minimum):
            return .outdated(current: current, minimum: minimum)
        case .broken(let message):
            return .unusable(message: message)
        }
    }
}
