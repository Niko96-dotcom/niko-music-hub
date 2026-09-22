import AppCore
import AppKit
import SwiftUI

/// Recovery-copy section for the Project Vault settings pane.
///
/// Always mounted, even when Project Vault is disabled: exporting and opening
/// a recovery copy must stay reachable exactly when the library is in doubt.
/// Export needs the live catalog (unavailable while the Export button is
/// disabled); opening a copy works through the standalone service entry point
/// even with a damaged current database. Launching the recovered library as a
/// separate app instance lives here in the app target so Core/AppCore stay
/// free of AppKit UI. User copy never exposes hashes or other internals.
struct ProjectVaultRecoverySection: View {
    let context: ToolContext

    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        SettingsSection(
            title: "Recovery copy",
            footer: "A recovery copy holds library metadata only, never Vault project files. "
                + "The copy opens as a separate library; the current library is never changed."
        ) {
            SettingsRow(
                "Export recovery metadata",
                description: "Saves library metadata for recovery. Vault project files need their own backup."
            ) {
                HubLabeledButton(
                    icon: "square.and.arrow.up",
                    label: isWorking ? "Working…" : "Export…",
                    style: .secondary,
                    help: "Save a recovery copy of the library metadata",
                    isEnabled: !isWorking && context.recoveryService != nil
                ) { exportRecovery() }
            }
            SettingsRowDivider()
            SettingsRow(
                "Open recovered library",
                description: "Opens a validated copy as a separate library with automation paused."
            ) {
                HubLabeledButton(
                    icon: "folder",
                    label: isWorking ? "Working…" : "Open…",
                    style: .secondary,
                    help: "Choose a recovery copy and open it as a separate library",
                    isEnabled: !isWorking
                ) { importRecovery() }
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
    }

    // MARK: - Export

    private func exportRecovery() {
        guard let service = context.recoveryService else {
            message = "The current catalog is unavailable, so a new export cannot be made."
            return
        }
        let panel = NSSavePanel()
        panel.prompt = "Export"
        panel.message = "Saves library metadata only. Back up the Vault folders separately."
        panel.nameFieldStringValue = Self.defaultBundleName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isWorking = true
        message = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try service.exportRecoveryBundle(to: destination)
                }.value
                await MainActor.run {
                    message = "Exported the recovery copy. Back up the Vault folders separately."
                    context.fileActions.revealInFinder(destination)
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    message = friendlyRecoveryError(error)
                    isWorking = false
                }
            }
        }
    }

    // MARK: - Import

    private func importRecovery() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose the exported recovery folder. It opens as a separate library."
        guard panel.runModal() == .OK, let bundleURL = panel.url else { return }
        isWorking = true
        message = nil
        Task {
            do {
                let recovered = try await Task.detached(priority: .userInitiated) {
                    try ProjectVaultRecoveryService.importRecoveredLibrary(from: bundleURL)
                }.value
                await MainActor.run {
                    launchRecoveredLibrary(recovered)
                }
            } catch {
                await MainActor.run {
                    message = friendlyRecoveryError(error)
                    // The bundle originals are preserved; reveal them for safekeeping.
                    context.fileActions.revealInFinder(bundleURL)
                    isWorking = false
                }
            }
        }
    }

    /// Launches the same app bundle as a NEW instance pointed at the recovered
    /// suite. The runtime already routes settings and support files into
    /// `Isolated/<suite>` for signed releases. Only runs after an explicit
    /// click and a successful import; never touches the current library.
    private func launchRecoveredLibrary(_ recovered: ProjectVaultRecoveredLibrary) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment[MusicHubRuntimeEnvironment.settingsSuiteKey] =
            recovered.settingsSuiteName
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            Task {
                await MainActor.run {
                    if error != nil {
                        message =
                            "The recovered copy is ready but could not open separately. "
                            + "It was left untouched."
                        context.fileActions.revealInFinder(recovered.supportDirectoryURL)
                    } else {
                        message =
                            "Opened the recovered library as a separate copy with automation paused."
                    }
                    isWorking = false
                }
            }
        }
    }

    // MARK: - Copy

    /// User-facing failure copy. Backend errors can carry checksums and paths;
    /// those internals are never surfaced.
    private func friendlyRecoveryError(_ error: Error) -> String {
        if let bundle = error as? ProjectVaultRecoveryBundle.BundleError {
            switch bundle {
            case .bundleNotFound:
                return "That folder is not a recovery copy. Choose the exported recovery folder."
            case .manifestInvalid, .settingsSchemaInvalid, .unsupportedVersion:
                return "That recovery copy cannot be read by this version. It was left untouched."
            case .checksumMismatch, .databaseIntegrityFailed:
                return "That recovery copy did not verify, so nothing was changed. Keep the original files."
            case .bundleOccupied, .recoveryDestinationOccupied:
                return "That location is already in use. Nothing was replaced."
            case .databaseBackupFailed, .ioFailed:
                return "The recovery action could not finish. Nothing was replaced."
            }
        }
        if let service = error as? ProjectVaultRecoveryServiceError {
            switch service {
            case .databaseUnavailable:
                return "The current catalog is unavailable, so a new export cannot be made."
            case .recoveredSuiteUnavailable:
                return "A separate recovered library could not be prepared. Nothing was changed."
            case .recoveryDestinationOccupied:
                return "That location is already in use. Nothing was replaced."
            case .ioFailed:
                return "The recovery action could not finish. Nothing was replaced."
            }
        }
        return "The recovery action could not finish. Nothing was replaced."
    }

    private static func defaultBundleName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "NikoMusicHub-Recovery-\(formatter.string(from: Date()))"
    }
}
