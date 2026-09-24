import AppCore
import AppKit
import Combine
import NikoMusicCore
import SwiftUI
import UniformTypeIdentifiers

struct ProjectVaultSettingsView: View {
    let context: ToolContext
    @Binding var settings: AppSettings
    let settingsAvailable: Bool
    let loginItemEnabled: Bool
    let onSave: (@escaping @Sendable (inout AppSettings) -> Void) -> Bool
    let onOpenLoginSetting: () -> Void

    @Environment(\.openWindow) private var openWindow

    @State private var showSetup = false
    @State private var message: String?
    @State private var isRunningDrill = false
    @State private var pendingVaultDiagnosticsDestination: URL?
    @State private var showReplaceDiagnosticsAlert = false
    @State private var showKeepLocalReview = false
    @State private var keepLocalBrowserVisited = false

    private var health: ProjectVaultHealth {
        ProjectVaultHealthEvaluator().evaluate(settings: settings)
    }

    var body: some View {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HubSectionHeader("Project Vault")
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow("Enable Project Vault") {
                    Toggle("Enable Project Vault", isOn: masterBinding)
                        .toggleStyle(.switch)
                        .tint(HubDesignSystem.Palette.indicator)
                        .labelsHidden()
                        .disabled(!settingsAvailable)
                }

                if settings.vault.isEnabled {
                    SettingsRowDivider()
                    folderRow(role: .active, title: "Active Projects")
                    SettingsRowDivider()
                    folderRow(role: .archive, title: "Archive / Vault")
                    SettingsRowDivider()
                    SettingsRow(
                        "Background scheduling",
                        description: "Inactive projects or low disk space. Off unless you turn it on. Done still asks."
                    ) {
                        Toggle("Background scheduling", isOn: vaultBinding(\.automaticArchiving))
                            .toggleStyle(.switch)
                            .tint(HubDesignSystem.Palette.indicator)
                            .labelsHidden()
                    }
                    SettingsRowDivider()
                    SettingsRow("Eligible after \(settings.vault.inactivityDays) inactive days") {
                        Stepper(
                            "Eligible after \(settings.vault.inactivityDays) inactive days",
                            value: intBinding(\.inactivityDays, range: 7...365)
                        )
                        .labelsHidden()
                    }
                    SettingsRowDivider()
                    SettingsRow("Start archiving below \(settings.vault.minimumFreeSpaceGiB) GiB free") {
                        Stepper(
                            "Start archiving below \(settings.vault.minimumFreeSpaceGiB) GiB free",
                            value: intBinding(\.minimumFreeSpaceGiB, range: 10...1000),
                            step: 10
                        )
                        .labelsHidden()
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        "Copying reserve: \(settings.vault.transferFreeSpaceReserveGiB) GiB",
                        description: "Before copying, allow room for the project plus this reserve. Marking Done skips the inactivity wait."
                    ) {
                        Stepper(
                            "Copying reserve: \(settings.vault.transferFreeSpaceReserveGiB) GiB",
                            value: intBinding(\.transferFreeSpaceReserveGiB, range: 1...1000)
                        )
                        .labelsHidden()
                    }
                    SettingsRowDivider()
                    SettingsRow("Keep previous generation \(settings.vault.keepPreviousGenerationDays) days") {
                        Stepper(
                            "Keep previous generation \(settings.vault.keepPreviousGenerationDays) days",
                            value: intBinding(\.keepPreviousGenerationDays, range: 7...365)
                        )
                        .labelsHidden()
                    }
                    SettingsRowDivider()
                    loginItemStatusRow
                    SettingsRowDivider()
                    SettingsRow("After archiving", description: "Removal always asks first.") {
                        HubSegmentedChoice(
                            "After archiving",
                            selection: intentBinding,
                            options: VaultSettings.SpaceIntent.allCases.map { .init($0, label: $0.label) }
                        )
                    }
                    SettingsRowDivider()
                    healthRows
                        .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    backupWarning
                    SettingsRowDivider()
                    SettingsRow("Emergency stop — pause all automation") {
                        Toggle(
                            "Emergency stop — pause all automation",
                            isOn: vaultBinding(\.automationEmergencyStop)
                        )
                        .toggleStyle(.switch)
                        .tint(HubDesignSystem.Colors.danger)
                        .labelsHidden()
                    }
                    SettingsRowDivider()
                    SettingsRow("Test Restore") {
                        HubLabeledButton(
                            icon: "checkmark.shield",
                            label: isRunningDrill ? "Testing…" : "Test",
                            style: .secondary,
                            help: "Run a restore using only an app-created temporary fixture",
                            isEnabled: !isRunningDrill
                        ) { runRestoreDrill() }
                    }
                    SettingsRowDivider()
                    SettingsRow("Export Diagnostics") {
                        HubLabeledButton(
                            icon: "doc.text",
                            label: "Export",
                            style: .ghost,
                            help: "Export path-free Project Vault settings and health"
                        ) { exportDiagnostics() }
                    }
                }

                // Review recovery stays visible even when Vault is disabled: a
                // whole-Vault repair defaults Vault off while still requiring
                // review, and the banner says so. Card contract (§4b): same
                // SettingsRow + divider treatment inside the card.
                if settings.vault.keepLocalReviewRequired {
                    SettingsRowDivider()
                    SettingsRow(
                        "Keep Local needs review",
                        description: ProjectVaultConfirmationCopy.keepLocalReviewRequiredSettingsNotice
                    ) {
                        HubLabeledButton(icon: "checkmark.shield", label: "Review…", style: .secondary) {
                            showKeepLocalReview = true
                        }
                    }
                }

                if let message {
                    SettingsRowDivider()
                    Text(message)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubSurface(.panel, cornerRadius: HubDesignSystem.Radius.popover)

            ProjectVaultRecoverySection(context: context)

            Text(settings.vault.isEnabled
                ? "Turning Project Vault off only stops scheduling. It never moves or deletes a project."
                : "Off by default. Read-only Archive browsing continues unchanged.")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showSetup) {
            ProjectVaultSetupSheet(
                settings: $settings,
                onChooseRoot: chooseRoot,
                onEnable: finishSetup,
                onCancel: { showSetup = false }
            )
        }
        .sheet(isPresented: $showKeepLocalReview) {
            KeepLocalReviewSheet(
                settings: settings,
                pinCount: settings.vault.keepLocalProjectIDs.count,
                browserVisited: keepLocalBrowserVisited,
                onOpenArchiveBrowser: openKeepLocalArchiveBrowser,
                onDone: doneKeepLocalReview,
                onCancel: { showKeepLocalReview = false }
            )
        }
        .onChange(of: settings.vault.keepLocalReviewRequired) { _, required in
            if required {
                keepLocalBrowserVisited = false
            }
        }
        // A visit before choosing a new root must not authorize review of the
        // new root: any Vault enablement or root change while review is
        // pending discards the recorded visit.
        .onChange(of: settings.vault.isEnabled) { _, _ in
            resetKeepLocalBrowserVisitIfReviewPending()
        }
        .onChange(of: settings.vault.activeRootID) { _, _ in
            resetKeepLocalBrowserVisitIfReviewPending()
        }
        .onChange(of: settings.vault.archiveRootID) { _, _ in
            resetKeepLocalBrowserVisitIfReviewPending()
        }
        // A successful settings repair may have dropped unreadable pins: require a fresh visit.
        .onReceive(context.settingsRepair.$repairGeneration.dropFirst()) { _ in keepLocalBrowserVisited = false }
        .alert(
            ProjectVaultDiagnosticsExportCopy.replaceTitle,
            isPresented: $showReplaceDiagnosticsAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingVaultDiagnosticsDestination = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Replace", role: .destructive) {
                if let destination = pendingVaultDiagnosticsDestination {
                    writeVaultDiagnostics(to: destination)
                }
            }
        } message: {
            Text(
                ProjectVaultDiagnosticsExportCopy.replaceMessage(
                    filename: pendingVaultDiagnosticsDestination?.lastPathComponent ?? "this file"
                )
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
            // Preserve saved preferences on re-enable: never reset thresholds
            // or re-enable background scheduling here. Background scheduling
            // stays opt-in (off for new setups unless the user turns it on).
            // New installs start safe with an explicit keep-a-copy intent;
            // re-enabling a previously configured Vault keeps its intent.
            if $0.vault.rolloutStage == .disabled {
                $0.vault.setSpaceIntent(.keepCopy)
                $0.vault.rolloutStage = .privateBeta
            }
        }) else { return }
        showSetup = false
        message = ProjectVaultConfirmationCopy.vaultEnabledSuccessMessage
    }

    /// Done Reviewing clears only the durable review flag against the latest
    /// stored settings, and only after the user both checked the box and
    /// visited Archive Browser (recorded in short-lived view state that
    /// survives sheet close/reopen and resets on a fresh repair) with a
    /// configured Vault (enabled, both folders chosen). Pins are never
    /// written here, so a pin changed while the sheet is open survives
    /// the save; clearing Emergency Stop or finishing setup never touches
    /// this flag. The policy guard runs on the view snapshot before saving
    /// (driving the disabled button) and again on the latest stored settings
    /// inside the save closure; when the save is a no-op (roots changed,
    /// Vault turned off, or the flag already cleared) no success message is
    /// shown.
    private func doneKeepLocalReview(confirmed: Bool) {
        let browserVisited = keepLocalBrowserVisited
        guard KeepLocalReviewPolicy.canCompleteReview(
            settings,
            confirmed: confirmed,
            browserVisited: browserVisited
        ) else { return }
        // updateSettings runs the mutation synchronously on this thread, so
        // recording its verdict in a box is race-free.
        let clearance = KeepLocalReviewClearanceBox(browserVisited: browserVisited)
        guard onSave({ settings in
            clearance.didClear = KeepLocalReviewPolicy.completeReview(
                &settings,
                confirmed: confirmed,
                browserVisited: clearance.browserVisited
            )
        }) else { return }
        guard clearance.didClear else { return }
        showKeepLocalReview = false
        keepLocalBrowserVisited = false
        message = ProjectVaultConfirmationCopy.keepLocalReviewClearedMessage
    }

    /// A visit before choosing a new root must not authorize review of the new
    /// root: while review is pending, any Vault enablement or root change
    /// discards the recorded browser visit so Done Reviewing needs a fresh one.
    private func resetKeepLocalBrowserVisitIfReviewPending() {
        if settings.vault.keepLocalReviewRequired {
            keepLocalBrowserVisited = false
        }
    }

    /// Review-sheet escape hatch: record the required browser visit, dismiss
    /// the sheet, route to the existing Archive Browser through the
    /// QuickAccessRouter, and bring the main window forward (opening it if
    /// closed). Re-pinning happens in the project's detail view; the sheet
    /// hint explains the return path. The visit survives sheet reopen and
    /// resets on a fresh repair obligation or after Done Reviewing.
    private func openKeepLocalArchiveBrowser() {
        keepLocalBrowserVisited = true
        showKeepLocalReview = false
        context.router.execute(.openTool(ToolFeatureID("archive-browser")))
        openWindow(id: HubMainWindowIdentity.sceneID)
        NSApp.activate()
    }

    @ViewBuilder
    private func folderRow(role: MusicRootRole, title: String) -> some View {
        let root = selectedRoot(role)
        SettingsRow(title, description: root?.displayName ?? "Not selected") {
            HubLabeledButton(icon: "folder", label: "Choose…", style: .ghost) {
                chooseRoot(role)
            }
        }
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
        SettingsRowDivider()
        if let warning = health.backupWarning {
            VStack(alignment: .leading, spacing: 6) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(HubDesignSystem.Colors.warning)
            }
            .font(HubDesignSystem.Typography.caption())
            .padding(8)
            .hubSurface(.card, state: .warning, cornerRadius: HubDesignSystem.Radius.row)
            .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsRowDivider()
        }
        SettingsRow(
            ProjectVaultConfirmationCopy.independentBackupToggleTitle,
            description: ProjectVaultConfirmationCopy.independentBackupToggleFooter
        ) {
            Toggle(
                ProjectVaultConfirmationCopy.independentBackupToggleTitle,
                isOn: vaultBinding(\.independentBackupConfirmed)
            )
            .toggleStyle(.switch)
            .tint(HubDesignSystem.Palette.indicator)
            .labelsHidden()
        }
    }

    private var intentBinding: Binding<VaultSettings.SpaceIntent> {
        Binding(get: { settings.vault.spaceIntent }, set: { value in
            updateVault { $0.setSpaceIntent(value) }
        })
    }

    private func vaultBinding(_ keyPath: WritableKeyPath<VaultSettings, Bool> & Sendable) -> Binding<Bool> {
        Binding(get: { settings.vault[keyPath: keyPath] }, set: { value in updateVault { $0[keyPath: keyPath] = value } })
    }

    private func intBinding(_ keyPath: WritableKeyPath<VaultSettings, Int> & Sendable, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { settings.vault[keyPath: keyPath] }, set: { value in updateVault { $0[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound) } })
    }

    @ViewBuilder
    private var loginItemStatusRow: some View {
        SettingsRow(VaultLaunchAtLoginPolicy.loginItemLabel(isEnabled: loginItemEnabled)) {
            HubLabeledButton(
                icon: "gearshape",
                label: "Open Login Setting",
                style: .ghost,
                help: "Open the General Open at login switch"
            ) {
                onOpenLoginSetting()
            }
        }
        if let warning = VaultLaunchAtLoginPolicy.warning(
            for: settings.vault,
            loginItemEnabled: loginItemEnabled
        ) {
            SettingsRowDivider()
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    /// NMH-055: vault diagnostics export goes through the system Save panel with a
    /// dated default name. An existing file is only replaced after confirmation.
    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = ProjectVaultDiagnosticsExportCopy.filename()
        panel.prompt = ProjectVaultDiagnosticsExportCopy.savePrompt
        panel.message = ProjectVaultDiagnosticsExportCopy.saveMessage
        panel.directoryURL = vaultDiagnosticsExportDirectory()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            pendingVaultDiagnosticsDestination = destination
            showReplaceDiagnosticsAlert = true
            return
        }
        writeVaultDiagnostics(to: destination)
    }

    private func vaultDiagnosticsExportDirectory() -> URL {
        let outputURL = settings.outputFolder.url
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return outputURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? outputURL
    }

    private func writeVaultDiagnostics(to destination: URL) {
        defer { pendingVaultDiagnosticsDestination = nil }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ProjectVaultDiagnosticsExporter.export(settings: settings, health: health, to: destination)
            context.fileActions.revealInFinder(destination)
            message = "Exported path-free Project Vault diagnostics."
        } catch let error as ProjectVaultDiagnosticsExportError {
            switch error {
            case .destinationInsideMusicRoot:
                message = ProjectVaultDiagnosticsExportCopy.archiveRootRecoveryMessage
            }
        } catch {
            message = "Diagnostics export failed: \(error.localizedDescription)"
        }
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Carries the Done Reviewing save verdict out of the `@Sendable` save
/// closure. The store runs the mutation synchronously on the calling thread,
/// so this never races; it only lets the view withhold the review-complete
/// success message when the save was a no-op (stale roots, Vault turned off,
/// or the flag already cleared).
private final class KeepLocalReviewClearanceBox: @unchecked Sendable {
    let browserVisited: Bool
    var didClear = false

    init(browserVisited: Bool) {
        self.browserVisited = browserVisited
    }
}

/// Keep Local review sheet: explains only readable pins survived (unreadable
/// entries could not be shown, raw backup saved), states the surviving pin
/// count, and requires an Archive Browser visit, an explicit check, and a
/// configured Vault (both folders chosen, Vault on) before Done Reviewing
/// clears the durable flag. The visit is parent-owned short-lived state so
/// the sheet can close and reopen; the checkbox is per-presentation.
/// Hub-only styling: no system blue.
private struct KeepLocalReviewSheet: View {
    let settings: AppSettings
    let pinCount: Int
    let browserVisited: Bool
    let onOpenArchiveBrowser: () -> Void
    let onDone: (Bool) -> Void
    let onCancel: () -> Void

    @State private var confirmed = false

    private var vaultReady: Bool {
        KeepLocalReviewPolicy.vaultRootsConfigured(in: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review Keep Local").font(.title2.weight(.semibold))
            Text(ProjectVaultConfirmationCopy.keepLocalReviewSheetMessage)
                .foregroundStyle(.secondary)
            Text(pinCount == 1 ? "1 project is currently pinned." : "\(pinCount) projects are currently pinned.")
                .foregroundStyle(.secondary)
            Text(ProjectVaultConfirmationCopy.keepLocalReviewSheetBrowserHint)
                .foregroundStyle(.secondary)
            Text(ProjectVaultConfirmationCopy.keepLocalReviewSheetVaultSetupHint)
                .foregroundStyle(.secondary)
            HubLabeledButton(
                icon: "archivebox",
                label: ProjectVaultConfirmationCopy.keepLocalReviewOpenBrowserLabel,
                style: .secondary,
                action: onOpenArchiveBrowser
            )
            if !browserVisited {
                Text("Opening Archive Browser is required before Done Reviewing.")
                    .foregroundStyle(.secondary)
            }
            if !vaultReady {
                Text(ProjectVaultConfirmationCopy.keepLocalReviewSheetVaultSetupRequiredLine)
                    .foregroundStyle(.secondary)
            }
            Toggle(ProjectVaultConfirmationCopy.keepLocalReviewSheetConfirmLabel, isOn: $confirmed)
                .toggleStyle(.switch)
                .tint(HubDesignSystem.Palette.indicator)
            HStack {
                HubLabeledButton(icon: "xmark", label: "Cancel", style: .ghost, action: onCancel)
                Spacer()
                HubLabeledButton(
                    icon: "checkmark",
                    label: "Done Reviewing",
                    style: .primary,
                    isEnabled: KeepLocalReviewPolicy.canCompleteReview(
                        settings,
                        confirmed: confirmed,
                        browserVisited: browserVisited
                    ),
                    action: { onDone(confirmed) }
                )
            }
        }
        .padding(24)
        .frame(width: 520)
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
            Text("Copies only — not a complete backup")
                .foregroundStyle(.secondary)
            setupRow("1", "Active Projects", settings.vault.activeRootID != nil, .active)
            setupRow("2", "Archive / Vault", settings.vault.archiveRootID != nil, .archive)
            Label("New archives keep a verified copy. Archive and free up space removes the Active copy only after you confirm.", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                HubLabeledButton(icon: "xmark", label: "Cancel", style: .ghost, action: onCancel)
                Spacer()
                HubLabeledButton(
                    icon: "checkmark",
                    label: "Enable Project Vault",
                    style: .primary,
                    isEnabled: settings.vault.activeRootID != nil && settings.vault.archiveRootID != nil,
                    action: onEnable
                )
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
            HubLabeledButton(icon: "folder", label: "Choose…", style: .ghost) { onChooseRoot(role) }
        }
    }
}
