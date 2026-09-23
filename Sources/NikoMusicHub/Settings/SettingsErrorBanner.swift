import AppCore
import SwiftUI

/// Full-width warning/error card shown above or below the pane content, with
/// an optional recovery action (verb + noun) on the trailing edge.
struct SettingsErrorBanner: View {
    enum Tone {
        case warning
        case error
        case success
    }

    let message: String
    let tone: Tone
    var detail: String? = nil
    var actionLabel: String? = nil
    var actionIcon: String = "wrench.and.screwdriver"
    var action: (() -> Void)? = nil

    private var foreground: Color {
        switch tone {
        case .warning: return HubDesignSystem.Colors.warning
        case .error: return HubDesignSystem.Colors.danger
        case .success: return HubDesignSystem.Palette.textPrimary
        }
    }

    private var symbol: String {
        tone == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var cardState: HubDesignSystem.ControlState {
        switch tone {
        case .warning: return .warning
        case .error: return .error
        case .success: return .normal
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
            VStack(alignment: .leading, spacing: 2) {
                Label(message, systemImage: symbol)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionLabel, let action {
                HubLabeledButton(icon: actionIcon, label: actionLabel, style: .secondary, action: action)
            }
        }
        .padding(HubDesignSystem.Spacing.section)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: cardState)
    }
}
