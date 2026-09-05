import AppCore
import NikoMusicCore
import SwiftUI

struct ProjectVaultSettingsView: View {
    let context: ToolContext
    @Binding var settings: AppSettings
    let settingsAvailable: Bool
    let onSave: (@escaping @Sendable (inout AppSettings) -> Void) -> Bool

    @State private var showSetup = false
    @State private var message: String?
    @State private var isRunningDrill = false

    private var health: ProjectVaultHealth {
        ProjectVaultHealthEvaluator().evaluate(settings: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HubSectionHeader("Project Vault")
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
                Toggle("Enable Project Vault", isOn: masterBinding)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.accent)
                    .disabled(!settingsAvailable)

                if settings.vault.isEnabled {
                    folderRow(role: .active, title: "Active Projects")
                    folderRow(role: .archive, title: "Archive / Vault")

                    Toggle("Automatic archiving", isOn: vaultBinding(\.automaticArchiving))
                        .toggleStyle(.switch)
                    Stepper("Eligible after \(settings.vault.inactivityDays) inactive days", value: intBinding(\.inactivityDays, range: 7...365))
                    Stepper("Start archiving below \(settings.vault.minimumFreeSpaceGiB) GiB free", value: intBinding(\.minimumFreeSpaceGiB, range: 10...1000), step: 10)
                    Stepper("Copying reserve: \(settings.vault.transferFreeSpaceReserveGiB) GiB", value: intBinding(\.transferFreeSpaceReserveGiB, range: 1...1000))
                    Text("Before copying, allow room for the project plus this reserve. Marking Done skips the inactivity wait.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("Keep previous generation \(settings.vault.keepPreviousGenerationDays) days", value: intBinding(\.keepPreviousGenerationDays, range: 7...365))
                    Toggle("Launch at login for automation", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)

                    Picker("Rollout", selection: rolloutBinding) {
                        ForEach(VaultSettings.RolloutStage.allCases, id: \.self) { stage in
                            Text(stage.label).tag(stage)
                        }
                    }
                    .pickerStyle(.menu)

                    healthRows
                    backupWarning

                    Toggle("Emergency stop — pause all automation", isOn: vaultBinding(\.automationEmergencyStop))
                        .toggleStyle(.switch)
                        .tint(HubDesignSystem.Colors.danger)

                    HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                        HubLabeledButton(
                            icon: "checkmark.shield",
                            label: isRunningDrill ? "Testing…" : "Test Restore",
                            style: .secondary,
                            help: "Run a restore using only an app-created temporary fixture",
                            isEnabled: !isRunningDrill
                        ) { runRestoreDrill() }
                        HubLabeledButton(
                            icon: "doc.text",
                            label: "Export Diagnostics",
                            style: .ghost,
                            help: "Export path-free Project Vault settings and health"
                        ) { exportDiagnostics() }
                    }
                }

                if let message {
                    Text(message)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(HubDesignSystem.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubSurface(.panel, cornerRadius: HubDesignSystem.Radius.panel)

            Text(settings.vault.isEnabled
                ? "Turning Project Vault off only stops scheduling. It never moves or deletes a project."
                : "Off by default. Read-only Archive browsing continues unchanged.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .sheet(isPresented: $showSetup) {
            ProjectVaultSetupSheet(
                settings: $settings,
                onChooseRoot: chooseRoot,
                onEnable: finishSetup,
                onCancel: { showSetup = false }
            )
        }
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { settings.vault.isEnabled },
            set: { enabled in
                if enabled {
                    showSetup = true
                } else {
                    if onSave({
                        $0.vault.isEnabled = false
                        $0.vault.automationEmergencyStop = true
                    }) { message = nil }
                }
            }
        )
    }

    private func finishSetup() {
        guard settings.vault.activeRootID != nil, settings.vault.archiveRootID != nil else {
            message = "Choose both folders before enabling Project Vault."
            return
        }
        guard onSave({
            $0.vault.isEnabled = true
            $0.vault.automationEmergencyStop = false
            $0.vault.automaticArchiving = true
            $0.vault.inactivityDays = 30
            $0.vault.minimumFreeSpaceGiB = 120
            $0.vault.transferFreeSpaceReserveGiB = 5
            $0.vault.keepPreviousGenerationDays = 30
            $0.vault.launchAtLogin = true
            $0.vault.rolloutStage = .privateBeta
        }) else { return }
        reconcileLaunchAtLogin(settings.vault)
        showSetup = false
        message = "Project Vault enabled in Private beta (copies only). Automatic removal remains unavailable."
    }

    @ViewBuilder
    private func folderRow(role: MusicRootRole, title: String) -> some View {
        let root = selectedRoot(role)
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                Text(root?.displayName ?? "Not selected")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            Spacer()
            HubLabeledButton(icon: "folder", label: "Choose…", style: .ghost) {
                chooseRoot(role)
            }
        }
        .padding(8)
        .hubSurface(.field)
    }

    private var healthRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(health.summary, systemImage: health.providerStatus == .offline ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark")
            Text("Last verified: \(dateLabel(settings.vault.lastSuccessfulVerificationAt))")
            Text("Last restore drill: \(dateLabel(settings.vault.lastRestoreDrillAt))")
        }
        .font(HubDesignSystem.Typography.caption())
        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
    }

    @ViewBuilder
    private var backupWarning: some View {
        if let warning = health.backupWarning {
            VStack(alignment: .leading, spacing: 6) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(HubDesignSystem.Colors.warning)
            }
            .font(HubDesignSystem.Typography.caption())
            .padding(8)
            .hubSurface(.card, state: .warning, cornerRadius: HubDesignSystem.Radius.row)
        }
        Toggle("I protect the Archive with an independent backup", isOn: vaultBinding(\.independentBackupConfirmed))
            .toggleStyle(.checkbox)
            .font(HubDesignSystem.Typography.caption())
    }

    private var rolloutBinding: Binding<VaultSettings.RolloutStage> {
        Binding(get: { settings.vault.rolloutStage }, set: { value in
            updateVault { $0.rolloutStage = value }
        })
    }

    private func vaultBinding(_ keyPath: WritableKeyPath<VaultSettings, Bool> & Sendable) -> Binding<Bool> {
        Binding(get: { settings.vault[keyPath: keyPath] }, set: { value in updateVault { $0[keyPath: keyPath] = value } })
    }

    private func intBinding(_ keyPath: WritableKeyPath<VaultSettings, Int> & Sendable, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { settings.vault[keyPath: keyPath] }, set: { value in updateVault { $0[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound) } })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { settings.vault.launchAtLogin }, set: { value in
            updateVault { $0.launchAtLogin = value }
            reconcileLaunchAtLogin(settings.vault)
        })
    }

    private func updateVault(_ mutation: @escaping @Sendable (inout VaultSettings) -> Void) {
        _ = onSave { mutation(&$0.vault) }
    }

    private func selectedRoot(_ role: MusicRootRole) -> StoredMusicRoot? {
        let id = role == .active ? settings.vault.activeRootID : settings.vault.archiveRootID
        return settings.musicRoots.first { $0.id == id && $0.role == role }
    }

    private func chooseRoot(_ role: MusicRootRole) {
        guard let folder = context.fileActions.chooseDirectory(prompt: role == .active ? "Choose Active Projects" : "Choose Archive / Vault") else { return }
        do {
            let current = try context.settingsStore.loadSettings()
            let candidate = try VaultRootManager().replacingRoot(role: role, with: folder, in: current)
            guard let replacement = candidate.musicRoots.first(where: { $0.role == role }) else { return }
            if onSave({ stored in
                stored.musicRoots.removeAll { $0.role == role }
                stored.musicRoots.append(replacement)
                switch role {
                case .active: stored.vault.activeRootID = replacement.id
                case .archive: stored.vault.archiveRootID = replacement.id
                case .scanOnly: break
                }
            }) { message = nil }
        } catch {
            message = "That folder cannot be used: \(error.localizedDescription)"
        }
    }

    private func reconcileLaunchAtLogin(_ vault: VaultSettings) {
        do { try VaultLaunchAtLoginReconciler(controller: context.launchAtLogin).reconcile(settings: vault) }
        catch { message = "Launch at login could not be updated: \(error.localizedDescription)" }
    }

    private func runRestoreDrill() {
        isRunningDrill = true
        Task {
            do {
                let result = try ProjectVaultRestoreDrill().run()
                await MainActor.run {
                    updateVault { $0.lastRestoreDrillAt = result.completedAt; $0.lastSuccessfulVerificationAt = result.completedAt }
                    message = "Synthetic restore verified \(result.fileCount) files; the archive fixture remained intact."
                    isRunningDrill = false
                }
            } catch {
                await MainActor.run { message = "Synthetic restore failed safely: \(error.localizedDescription)"; isRunningDrill = false }
            }
        }
    }

    private func exportDiagnostics() {
        let destination = settings.outputFolder.url.appendingPathComponent("project-vault-diagnostics.txt")
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ProjectVaultDiagnosticsExporter.export(settings: settings, health: health, to: destination)
            context.fileActions.revealInFinder(destination)
            message = "Exported path-free Project Vault diagnostics."
        } catch { message = "Diagnostics export failed: \(error.localizedDescription)" }
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ProjectVaultSetupSheet: View {
    @Binding var settings: AppSettings
    let onChooseRoot: (MusicRootRole) -> Void
    let onEnable: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up Project Vault").font(.title2.weight(.semibold))
            Text("Active Projects is where you work. Archive / Vault holds verified generations. Start with copies only; this is not a complete backup strategy.")
                .foregroundStyle(.secondary)
            setupRow("1", "Active Projects", settings.vault.activeRootID != nil, .active)
            setupRow("2", "Archive / Vault", settings.vault.archiveRootID != nil, .archive)
            Label("Private beta is selected. Automatic removal is not enabled for artist libraries.", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Enable Project Vault", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .disabled(settings.vault.activeRootID == nil || settings.vault.archiveRootID == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func setupRow(_ number: String, _ title: String, _ selected: Bool, _ role: MusicRootRole) -> some View {
        HStack {
            Text(number).font(.headline).frame(width: 24)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(selected ? "Folder selected" : "Choose a folder").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose…") { onChooseRoot(role) }
        }
    }
}
