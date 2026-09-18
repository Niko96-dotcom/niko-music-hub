import AppCore
import SwiftUI

/// Full-width warning/error card shown above or below the pane content.
struct SettingsErrorBanner: View {
    enum Tone {
        case warning
        case error
    }

    let message: String
    let tone: Tone

    private var foreground: Color {
        switch tone {
        case .warning: return HubDesignSystem.Colors.warning
        case .error: return HubDesignSystem.Colors.danger
        }
    }

    private var cardState: HubDesignSystem.ControlState {
        switch tone {
        case .warning: return .warning
        case .error: return .error
        }
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HubDesignSystem.Spacing.section)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: cardState)
    }
}
