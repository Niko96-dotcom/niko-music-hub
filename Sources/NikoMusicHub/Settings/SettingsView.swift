import AppCore
import AppKit
import AppUpdates
import Combine
import FeatureArchiveBrowser
import NikoMusicCore
import SwiftUI

@MainActor
final class HubSettingsSession: ObservableObject {
    let context: ToolContext
    let appearanceController: AppAppearanceController
    let updateController: AppUpdateController
    let shellSession: HubShellSession

    @Published var settings: AppSettings = .default
    @Published var launchAtLogin = false
    @Published var launchAtLoginError: String?
    @Published var settingsLoadError: String?
    @Published var saveError: String?
    @Published var helperPathError: String?

    private var settingsObserverCancellable: AnyCancellable?

    let recordingDurationChoices = RecordingDurationOptions.supportedMinutes

    init(
        context: ToolContext,
        appearanceController: AppAppearanceController,
        updateController: AppUpdateController,
        shellSession: HubShellSession
    ) {
        self.context = context
        self.appearanceController = appearanceController
        self.updateController = updateController
        self.shellSession = shellSession
        self.settings = context.appSettings.settings
        settingsObserverCancellable = context.appSettings.$settings
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self else { return }
                self.settings = settings
            }
    }

    var updatesFooter: String {
        updateController.status.isUnavailable
            ? "Update checks are switched off for this build."
            : "Updates are downloaded from the signed release feed and verified before they are installed."
    }

    var maxRecordingBinding: Binding<Int> {
        Binding(
            get: { self.settings.maxRecordingDurationMinutes },
            set: { newValue in
                let normalized = RecordingDurationOptions.normalized(newValue)
                let settings = self.settings
                let previous = settings.maxRecordingDurationMinutes
                self.settings.maxRecordingDurationMinutes = normalized
                if !self.persistSettings({ $0.maxRecordingDurationMinutes = normalized }) {
                    self.settings.maxRecordingDurationMinutes = previous
                }
            }
        )
    }

    var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { self.settings.appearance },
            set: { newValue in
                let settings = self.settings
                let previous = settings.appearance
                self.settings.appearance = newValue
                self.appearanceController.apply(newValue)
                if !self.persistSettings({ $0.appearance = newValue }) {
                    self.settings.appearance = previous
                    self.appearanceController.apply(previous)
                }
            }
        )
    }

    var scanExclusionBinding: Binding<String> {
        Binding(
            get: { self.settings.scanExclusionTerms },
            set: { newValue in
                let previous = self.settings.scanExclusionTerms
                self.settings.scanExclusionTerms = newValue
                if !self.persistSettings({ $0.scanExclusionTerms = newValue }) {
                    self.settings.scanExclusionTerms = previous
                }
            }
        )
    }

    var showMenuBarExtraBinding: Binding<Bool> {
        Binding(
            get: { self.settings.showMenuBarExtra },
            set: { newValue in
                let previous = self.settings.showMenuBarExtra
                self.settings.showMenuBarExtra = newValue
                if self.persistSettings({ $0.showMenuBarExtra = newValue }) {
                    self.shellSession.applyShowMenuBarExtra(newValue)
                } else {
                    self.settings.showMenuBarExtra = previous
                }
            }
        )
    }

    func refresh() {
        do {
            settings = try context.settingsStore.loadSettings()
            settings.maxRecordingDurationMinutes = RecordingDurationOptions.normalized(
                settings.maxRecordingDurationMinutes
            )
            settingsLoadError = nil
            appearanceController.apply(settings.appearance)
            shellSession.applyShowMenuBarExtra(settings.showMenuBarExtra)
        } catch {
            settings = .default
            settingsLoadError = "Could not load settings. Existing settings were left untouched: \(error.localizedDescription)"
            context.diagnostics.log(.error, "Settings load failed: \(error)")
        }
        launchAtLogin = context.launchAtLogin.isEnabled()
        launchAtLoginError = nil
        saveError = nil
        helperPathError = nil
    }

    @discardableResult
    func persistSettings(_ update: @escaping @Sendable (inout AppSettings) -> Void) -> Bool {
        guard settingsLoadError == nil else {
            saveError = "Settings were not saved because the current settings could not be loaded."
            return false
        }
        do {
            try context.settingsStore.updateSettings(update)
            settings = try context.settingsStore.loadSettings()
            saveError = nil
            return true
        } catch {
            saveError = "Could not save settings."
            context.diagnostics.log(.error, "Settings save failed")
            return false
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        // A failed toggle reverts `launchAtLogin` to the real state, which fires
        // onChange again with that state; bail out so the retry cannot clear the
        // error just shown (or unregister a login item awaiting user approval).
        guard enabled != context.launchAtLogin.isEnabled() else { return }
        do {
            try context.launchAtLogin.setEnabled(enabled)
            launchAtLogin = context.launchAtLogin.isEnabled()
            launchAtLoginError = nil
        } catch let error as LaunchAtLoginError {
            launchAtLogin = context.launchAtLogin.isEnabled()
            switch error {
            case .registrationFailed(let message):
                launchAtLoginError = message
            }
        } catch {
            launchAtLogin = context.launchAtLogin.isEnabled()
            launchAtLoginError = error.localizedDescription
        }
    }

    func chooseOutputFolder() {
        guard settingsLoadError == nil else {
            saveError = "Settings were not saved because the current settings could not be loaded."
            return
        }
        guard let folder = context.fileActions.chooseOutputFolder() else { return }
        do {
            try OutputWriteGuard().validateCanWriteOutput(
                to: folder,
                archiveRoots: settings.archiveRoots.map(\.url)
            )
        } catch {
            saveError = error.localizedDescription
            return
        }
        let previous = settings.outputFolder
        settings.outputFolder = StoredFolderLocation(url: folder)
        if !persistSettings({ $0.outputFolder = StoredFolderLocation(url: folder) }) {
            settings.outputFolder = previous
        }
    }
}

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow

    let pane: HubSettingsPane

    @ObservedObject var session: HubSettingsSession
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    @ObservedObject var router: QuickAccessRouter

    init(
        session: HubSettingsSession,
        archiveViewModel: ArchiveBrowserViewModel,
        router: QuickAccessRouter,
        pane: HubSettingsPane
    ) {
        self.session = session
        self.archiveViewModel = archiveViewModel
        self.router = router
        self.pane = pane
    }

    var body: some View {
        // Fixed 680pt column, centered: hubToolContentColumn's 680 cap already
        // includes its own horizontal padding (real content is 648), so an outer
        // 712 box would pool 32pt of slack on the right. 680 fits the padded
        // column exactly — zero slack, symmetric gaps by construction.
        HubToolPage {
            settingsLoadErrorBanner
            paneContent
            saveErrorBanner
        }
        .frame(width: HubToolLayout.maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general:
            SettingsGeneralSection(
                settingsAvailable: session.settingsLoadError == nil,
                appearance: session.appearanceBinding,
                launchAtLogin: $session.launchAtLogin,
                launchAtLoginError: session.launchAtLoginError,
                showMenuBarExtra: session.showMenuBarExtraBinding,
                onLaunchAtLoginChange: session.setLaunchAtLogin
            )
            SettingsOutputSection(
                outputFolderPath: session.settings.outputFolder.url.path,
                settingsAvailable: session.settingsLoadError == nil,
                onChooseFolder: session.chooseOutputFolder,
                onRevealFolder: revealOutputFolder
            )
            SettingsAudioConversionSection(
                preset: session.settings.audioPreset,
                onEditInConverter: openWAVConverter
            )
            SettingsRecordingSection(
                maxDurationMinutes: session.maxRecordingBinding,
                durationChoices: session.recordingDurationChoices,
                settingsAvailable: session.settingsLoadError == nil
            )
            SettingsPrivacySection {
                SystemPrivacySettings.openSystemAudioRecordingSettings()
            }
        case .archive:
            SettingsArchivePane(
                roots: archiveViewModel.roots,
                scanExclusions: session.scanExclusionBinding,
                onAddRoot: addArchiveRoot,
                onRemoveRoot: removeArchiveRoot
            )
        case .vault:
            ProjectVaultSettingsView(
                context: session.context,
                settings: $session.settings,
                settingsAvailable: session.settingsLoadError == nil,
                loginItemEnabled: session.launchAtLogin,
                onSave: saveProjectVaultSettings,
                onOpenLoginSetting: openLoginSetting
            )
        case .helpers:
            SettingsHelpersPane(
                helperTools: session.settings.helperTools,
                settingsAvailable: session.settingsLoadError == nil,
                helperPathError: $session.helperPathError,
                chooseExecutable: { prompt in
                    session.context.fileActions.chooseExecutable(prompt: prompt)
                },
                onSetPath: setHelperToolPath
            )
        case .updates:
            SettingsUpdatesPane(
                controller: session.updateController,
                footer: session.updatesFooter
            )
        }
    }

    @ViewBuilder
    private var settingsLoadErrorBanner: some View {
        if let settingsLoadError = session.settingsLoadError {
            SettingsErrorBanner(message: settingsLoadError, tone: .warning)
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let saveError = session.saveError {
            SettingsErrorBanner(message: saveError, tone: .error)
        }
    }

    private func revealOutputFolder() {
        session.context.fileActions.revealInFinder(session.settings.outputFolder.url)
    }

    private func addArchiveRoot() {
        guard let folder = session.context.fileActions.chooseDirectory(prompt: "Choose Archive Root") else { return }
        archiveViewModel.addRoot(folder)
    }

    private func removeArchiveRoot(_ root: URL) {
        archiveViewModel.removeRoot(root)
    }

    private func setHelperToolPath(_ tool: SettingsHelperTool, to url: URL?) {
        session.settings.helperTools[keyPath: tool.keyPath] = url
        session.persistSettings { $0.helperTools[keyPath: tool.keyPath] = url }
    }

    private func saveProjectVaultSettings(_ update: @escaping @Sendable (inout AppSettings) -> Void) -> Bool {
        let saved = session.persistSettings(update)
        if saved {
            archiveViewModel.applyProjectVaultSettingsChange()
        }
        return saved
    }

    private func openLoginSetting() {
        router.requestSettingsPane(.general)
    }

    private func openWAVConverter() {
        router.execute(.openTool(ToolFeatureID("wav-converter")))
        openWindow(id: "main")
        NSApp.activate()
    }
}

// MARK: - General section

/// "General" section: appearance chips, the single Open-at-login writer and the
/// menu bar extra toggle. Kept in this file with the session — the source-pinned
/// AppCore tests read the login toggle and menu bar copy from here.
private struct SettingsGeneralSection: View {
    let settingsAvailable: Bool
    @Binding var appearance: AppAppearance
    @Binding var launchAtLogin: Bool
    let launchAtLoginError: String?
    @Binding var showMenuBarExtra: Bool
    let onLaunchAtLoginChange: (Bool) -> Void

    var body: some View {
        SettingsSection(title: "General") {
            SettingsRow("Appearance") {
                HubChoiceChips(
                    "Appearance",
                    selection: $appearance,
                    choices: AppAppearance.allCases.map { .init($0, label: $0.label, help: $0.help) }
                )
                .disabled(!settingsAvailable)
            }
            SettingsRowDivider()
            SettingsRow(
                "Open at login",
                description: "Project Vault automatic archiving needs this to run while you are away"
            ) {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.indicator)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, enabled in
                        onLaunchAtLoginChange(enabled)
                    }
            }
            if let launchAtLoginError {
                SettingsRowDivider()
                inlineWarning(launchAtLoginError)
                    .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                    .padding(.vertical, 10)
            }
            SettingsRowDivider()
            SettingsRow("Show menu bar extra") {
                Toggle("Show menu bar extra", isOn: $showMenuBarExtra)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.indicator)
                    .labelsHidden()
                    .disabled(!settingsAvailable)
            }
        }
    }

    private func inlineWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Colors.warning)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HubDesignSystem.Spacing.controlGap)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
    }
}

// MARK: - Archive pane

/// Music archive pane: scan roots (read-only), board compaction, scan exclusions.
private struct SettingsArchivePane: View {
    let roots: [URL]
    @Binding var scanExclusions: String
    let onAddRoot: () -> Void
    let onRemoveRoot: (URL) -> Void
    /// Board preference (read by ArchiveBoardView via the same key).
    @AppStorage("hub.archive.compactEmptyStages") private var compactEmptyStages = false

    var body: some View {
        SettingsSection(
            title: "Music archive",
            footer: "Read-only scan roots — files are never renamed, moved, or deleted"
        ) {
            archiveRootsSection
            SettingsRowDivider()
            SettingsRow("Compact empty board stages") {
                Toggle("Compact empty board stages", isOn: $compactEmptyStages)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.indicator)
                    .labelsHidden()
            }
            SettingsRowDivider()
            SettingsRow(
                "Scan exclusions",
                description: "Comma-separated folder-name terms to skip during scan."
            ) {
                TextField(
                    "Scan exclusions",
                    text: $scanExclusions,
                    prompt: Text("backup, tmp, archive")
                        .foregroundColor(HubDesignSystem.Palette.textTertiary)
                )
                .accessibilityHint("Comma-separated folder-name terms to skip during scan.")
                .textFieldStyle(.plain)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
                .frame(minWidth: 140, maxWidth: 260)
            }
        }
    }

    @ViewBuilder
    private var archiveRootsSection: some View {
        if roots.isEmpty {
            Text("No archive roots — add the folder that holds your song projects")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(Array(roots.enumerated()), id: \.element) { index, root in
                if index > 0 {
                    SettingsRowDivider()
                }
                archiveRootRow(root)
            }
        }
        SettingsRowDivider()
        SettingsRow("Add archive root") {
            HubLabeledButton(
                icon: "folder.badge.plus",
                label: "Add",
                style: .secondary,
                help: "Choose a Cubase or Ableton projects folder to scan",
                action: onAddRoot
            )
        }
    }

    private func archiveRootRow(_ root: URL) -> some View {
        SettingsRow(
            root.lastPathComponent.isEmpty ? "Archive Root" : root.lastPathComponent,
            description: root.path
        ) {
            HubIconButton(
                systemImage: "trash",
                accessibilityLabel: "Remove archive root",
                help: "Remove \(root.lastPathComponent) from scan list",
                role: .destructive
            ) {
                onRemoveRoot(root)
            }
        }
    }
}

// MARK: - Helpers pane

/// The four overridable helper executables, in pane order.
private enum SettingsHelperTool {
    case ffmpeg
    case ffprobe
    case ytDlp
    case demucsMlx

    var label: String {
        switch self {
        case .ffmpeg: return "FFmpeg"
        case .ffprobe: return "ffprobe"
        case .ytDlp: return "yt-dlp"
        case .demucsMlx: return "demucs-mlx"
        }
    }

    var prompt: String {
        "Choose \(label)"
    }

    var keyPath: WritableKeyPath<HelperToolSettings, URL?> {
        switch self {
        case .ffmpeg: return \.ffmpeg
        case .ffprobe: return \.ffprobe
        case .ytDlp: return \.ytDlp
        case .demucsMlx: return \.demucsMlx
        }
    }
}

/// Helper tools pane: one row per executable with choose / auto-detect and an
/// inline validation warning under the offending row.
private struct SettingsHelpersPane: View {
    let helperTools: HelperToolSettings
    let settingsAvailable: Bool
    @Binding var helperPathError: String?
    let chooseExecutable: (String) -> URL?
    let onSetPath: (SettingsHelperTool, URL?) -> Void

    var body: some View {
        SettingsSection(
            title: "Helper tools",
            footer: "Only needed when Homebrew installs are not on PATH"
        ) {
            helperPathRow(.ffmpeg)
            SettingsRowDivider()
            helperPathRow(.ffprobe)
            SettingsRowDivider()
            helperPathRow(.ytDlp)
            SettingsRowDivider()
            helperPathRow(.demucsMlx)
        }
    }

    private func helperPathRow(_ tool: SettingsHelperTool) -> some View {
        let label = tool.label
        let url = helperTools[keyPath: tool.keyPath]
        return Group {
            SettingsRow(
                label,
                description: url?.path ?? "Auto-detect"
            ) {
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    HubLabeledButton(
                        icon: "ellipsis",
                        label: tool.prompt,
                        style: .ghost,
                        isEnabled: settingsAvailable
                    ) {
                        choosePath(for: tool)
                    }

                    if url != nil {
                        HubIconButton(
                            systemImage: "xmark",
                            accessibilityLabel: "Use auto-detect for \(label)",
                            help: "Use auto-detect for \(label)",
                            isEnabled: settingsAvailable
                        ) {
                            onSetPath(tool, nil)
                        }
                    }
                }
            }
            if let helperPathError,
               helperPathError.hasPrefix("\(label): ") {
                SettingsRowDivider()
                Text(helperPathError)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func choosePath(for tool: SettingsHelperTool) {
        guard let chosen = chooseExecutable(tool.prompt) else { return }
        if let validationError = HelperExecutableValidation.validate(url: chosen) {
            helperPathError = "\(tool.label): \(validationError)"
            return
        }
        helperPathError = nil
        onSetPath(tool, chosen)
    }
}

// MARK: - Settings section

/// Titled group card. Rows go directly inside (no cards inside cards); the
/// optional footer sits under the card in caption type.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
            HubSectionHeader(title)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubSurface(.panel, state: .normal, cornerRadius: HubDesignSystem.Radius.popover)

            if let footer {
                Text(footer)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
