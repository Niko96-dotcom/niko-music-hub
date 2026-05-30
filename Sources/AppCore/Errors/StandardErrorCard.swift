import SwiftUI

public struct StandardErrorCard: View {
    public let card: AppErrorCard
    public var onRecovery: ((AppErrorCard.RecoveryActionType) -> Void)?

    public init(card: AppErrorCard, onRecovery: ((AppErrorCard.RecoveryActionType) -> Void)? = nil) {
        self.card = card
        self.onRecovery = onRecovery
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: card.icon)
                    .foregroundStyle(labelColor)
                Text(card.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(labelColor)
            }

            Text(card.body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(card.recoveryActions, id: \.label) { action in
                    recoveryButton(for: action)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var labelColor: Color {
        switch card.category {
        case .permission:
            return .orange
        case .helperTool:
            return .red
        case .conversionFile:
            return .red
        case .inputURL:
            return .orange
        }
    }

    @ViewBuilder
    private func recoveryButton(for action: AppErrorCard.RecoveryAction) -> some View {
        switch action.style {
        case .primary:
            Button(action.label) {
                executeRecovery(action.action)
            }
            .buttonStyle(.borderedProminent)
        case .secondary:
            Button(action.label) {
                executeRecovery(action.action)
            }
            .buttonStyle(.bordered)
        case .destructive:
            Button(action.label) {
                executeRecovery(action.action)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
        }
    }

    private func executeRecovery(_ action: AppErrorCard.RecoveryActionType) {
        if let onRecovery {
            onRecovery(action)
        }
        switch action {
        case .openSystemSettings:
            SystemPrivacySettings.openSystemAudioRecordingSettings()
        case .tryAgain, .dismiss:
            break
        case .chooseToolPath:
            break
        case .revealInFinder:
            break
        case .openTerminal:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }
}