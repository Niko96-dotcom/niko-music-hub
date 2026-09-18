import AppCore
import NikoMusicCore
import SwiftUI

/// NMH-054 fallback when byte size cannot be read: one honest check per
/// restore phase instead of a determinate-looking bar.
struct ProjectVaultRestorePhaseChecklist: View {
    let current: VaultRestorePhase

    private var phases: [VaultRestorePhase] { ProjectVaultRestoreProgress.checklistPhases }
    private var currentIndex: Int? { phases.firstIndex(of: current) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(phases, id: \.self) { phase in
                let index = phases.firstIndex(of: phase) ?? 0
                let done = currentIndex.map { index < $0 } ?? false
                let isCurrent = currentIndex.map { index == $0 } ?? false
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : (isCurrent ? "arrow.triangle.2.circlepath" : "circle"))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(done || isCurrent ? HubDesignSystem.Palette.accent : HubDesignSystem.Palette.textTertiary)
                    Text(ProjectVaultRestoreProgress(phase: phase).title)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(isCurrent ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(ProjectVaultRestoreProgress(phase: phase).title)\(done ? ", done" : (isCurrent ? ", in progress" : ", pending"))")
            }
        }
    }
}
