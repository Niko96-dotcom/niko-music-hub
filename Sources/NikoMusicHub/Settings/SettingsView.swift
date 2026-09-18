import AppCore
import AppKit
import AppUpdates
import FeatureAudioConverter
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
        settings.outputFolder = StoredFolderLocation(url: folder)
        persistSettings { $0.outputFolder = StoredFolderLocation(url: folder) }
    }
}

struct SettingsView: View {
    @ObservedObject var session: HubSettingsSession
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    @ObservedObject var router: QuickAccessRouter
    let pane: HubSettingsPane
    /// Board preference (read by ArchiveBoardView via the same key).
    @AppStorage("hub.archive.compactEmptyStages") private var compactEmptyStages = false

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HubToolPage {
            settingsLoadErrorBanner
            paneContent
            saveErrorBanner
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general:
            generalPane
        case .archive:
            archivePane
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
            helpersPane
        case .updates:
            updatesPane
        }
    }

    @ViewBuilder
    private var generalPane: some View {
        SettingsSection(
            title: "General",
            importance: .high
        ) {
            SettingsRow("Appearance") {
                HubChoiceChips(
                    "Appearance",
                    selection: session.appearanceBinding,
                    choices: AppAppearance.allCases.map { .init($0, label: $0.label, help: $0.help) }
                )
                .disabled(session.settingsLoadError != nil)
            }
            SettingsRowDivider()
            SettingsRow(
                "Open at login",
                description: "Project Vault automatic archiving needs this to run while you are away"
            ) {
                Toggle("Open at login", isOn: $session.launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.accent)
                    .labelsHidden()
                    .onChange(of: session.launchAtLogin) { _, enabled in
                        session.setLaunchAtLogin(enabled)
                    }
            }
            if let launchAtLoginError = session.launchAtLoginError {
                SettingsRowDivider()
                inlineWarning(launchAtLoginError)
                    .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                    .padding(.vertical, 10)
            }
            SettingsRowDivider()
            SettingsRow("Show menu bar extra") {
                Toggle("Show menu bar extra", isOn: session.showMenuBarExtraBinding)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.accent)
                    .labelsHidden()
                    .disabled(session.settingsLoadError != nil)
            }
        }

        SettingsSection(
            title: "Output",
            importance: .high,
            footer: "Also listed in the Output Inbox"
        ) {
            SettingsRow(
                "Output folder",
                description: session.settings.outputFolder.url.path
            ) {
                HubLabeledButton(
                    icon: "folder.badge.gearshape",
                    label: "Choose",
                    style: .secondary,
                    help: "Pick where exports and recordings are saved",
                    isEnabled: session.settingsLoadError == nil
                ) {
                    session.chooseOutputFolder()
                }
            }
            SettingsRowDivider()
            SettingsRow("Reveal in Finder") {
                HubLabeledButton(
                    icon: "folder",
                    label: "Reveal",
                    style: .ghost,
                    help: "Show output folder in Finder"
                ) {
                    session.context.fileActions.revealInFinder(session.settings.outputFolder.url)
                }
            }
        }

        SettingsSection(
            title: "Audio conversion",
            importance: .medium,
            footer: "Default for the converter and recorder; each batch can override it"
        ) {
            SettingsRow("Sample rate") {
                Text(AudioConverterViewModel.sampleRateLabel(for: session.settings.audioPreset.sampleRate))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            SettingsRowDivider()
            SettingsRow("Bit depth") {
                Text("\(session.settings.audioPreset.bitDepth)-bit")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            SettingsRowDivider()
            SettingsRow("Channels") {
                Text(channelModeLabel(session.settings.audioPreset.channelMode))
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            }
            SettingsRowDivider()
            SettingsRow("Edit in WAV Converter") {
                HubLabeledButton(
                    icon: "waveform",
                    label: "Edit",
                    style: .secondary,
                    help: "Opens WAV Converter to change the default preset"
                ) {
                    openWAVConverter()
                }
            }
        }

        SettingsSection(
            title: "Recording",
            importance: .medium
        ) {
            SettingsRow("Max duration") {
                Picker("Max duration", selection: session.maxRecordingBinding) {
                    ForEach(session.recordingDurationChoices, id: \.self) { minutes in
                        Text(RecordingDurationOptions.label(for: minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(session.settingsLoadError != nil)
            }
        }

        SettingsSection(
            title: "Privacy & recording",
            importance: .low,
            footer: "Only Audio Recorder needs this; a rebuilt app may ask again"
        ) {
            SettingsRow(
                "Open System Settings",
                description: "Enable Niko Music Hub under Screen & System Audio Recording so Recorder can capture Mac output to a WAV in your output folder."
            ) {
                HubLabeledButton(
                    icon: "lock.shield",
                    label: "Open",
                    style: .primary,
                    help: "Open Screen & System Audio Recording in System Settings"
                ) {
                    SystemPrivacySettings.openSystemAudioRecordingSettings()
                }
            }
        }
    }

    @ViewBuilder
    private var archivePane: some View {
        SettingsSection(
            title: "Music archive",
            importance: .high,
            footer: "Read-only scan roots — files are never renamed, moved, or deleted"
        ) {
            archiveRootsSection
            SettingsRowDivider()
            SettingsRow("Compact empty board stages") {
                Toggle("Compact empty board stages", isOn: $compactEmptyStages)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.accent)
                    .labelsHidden()
            }
            SettingsRowDivider()
            SettingsRow(
                "Scan exclusions",
                description: "Comma-separated folder-name terms to skip during scan."
            ) {
                TextField(
                    "Scan exclusions",
                    text: session.scanExclusionBinding,
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
    private var helpersPane: some View {
        SettingsSection(
            title: "Helper tools",
            importance: .low,
            footer: "Only needed when Homebrew installs are not on PATH"
        ) {
            helperPathRow(label: "FFmpeg", url: session.settings.helperTools.ffmpeg, prompt: "Choose FFmpeg") { url in
                session.settings.helperTools.ffmpeg = url
                session.persistSettings { $0.helperTools.ffmpeg = url }
            }
            SettingsRowDivider()
            helperPathRow(label: "ffprobe", url: session.settings.helperTools.ffprobe, prompt: "Choose ffprobe") { url in
                session.settings.helperTools.ffprobe = url
                session.persistSettings { $0.helperTools.ffprobe = url }
            }
            SettingsRowDivider()
            helperPathRow(label: "yt-dlp", url: session.settings.helperTools.ytDlp, prompt: "Choose yt-dlp") { url in
                session.settings.helperTools.ytDlp = url
                session.persistSettings { $0.helperTools.ytDlp = url }
            }
            SettingsRowDivider()
            helperPathRow(label: "demucs-mlx", url: session.settings.helperTools.demucsMlx, prompt: "Choose demucs-mlx") { url in
                session.settings.helperTools.demucsMlx = url
                session.persistSettings { $0.helperTools.demucsMlx = url }
            }
        }
    }

    @ViewBuilder
    private var updatesPane: some View {
        SettingsSection(
            title: "Updates",
            importance: .medium,
            footer: session.updatesFooter
        ) {
            AppUpdateSettingsContent(controller: session.updateController)
                .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var archiveRootsSection: some View {
        if archiveViewModel.roots.isEmpty {
            Text("No archive roots — add the folder that holds your song projects")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(Array(archiveViewModel.roots.enumerated()), id: \.element) { index, root in
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
                action: addArchiveRoot
            )
        }
    }

    @ViewBuilder
    private var settingsLoadErrorBanner: some View {
        if let settingsLoadError = session.settingsLoadError {
            Label(settingsLoadError, systemImage: "exclamationmark.triangle.fill")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HubDesignSystem.Spacing.section)
                .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let saveError = session.saveError {
            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Colors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HubDesignSystem.Spacing.section)
                .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .error)
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
                archiveViewModel.removeRoot(root)
            }
        }
    }

    private func helperPathRow(
        label: String,
        url: URL?,
        prompt: String,
        onSet: @escaping (URL?) -> Void
    ) -> some View {
        Group {
            SettingsRow(
                label,
                description: url?.path ?? "Auto-detect"
            ) {
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    HubLabeledButton(
                        icon: "ellipsis",
                        label: prompt,
                        style: .ghost,
                        isEnabled: session.settingsLoadError == nil
                    ) {
                        guard let chosen = session.context.fileActions.chooseExecutable(prompt: prompt) else { return }
                        if let validationError = HelperExecutableValidation.validate(url: chosen) {
                            session.helperPathError = "\(label): \(validationError)"
                            return
                        }
                        session.helperPathError = nil
                        onSet(chosen)
                    }

                    if url != nil {
                        HubIconButton(
                            systemImage: "xmark",
                            accessibilityLabel: "Use auto-detect for \(label)",
                            help: "Use auto-detect for \(label)",
                            isEnabled: session.settingsLoadError == nil
                        ) {
                            onSet(nil)
                        }
                    }
                }
            }
            if let helperPathError = session.helperPathError,
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

    private func inlineWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Colors.warning)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HubDesignSystem.Spacing.controlGap)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
    }

    private func channelModeLabel(_ mode: AudioChannelMode) -> String {
        switch mode {
        case .preserveMonoStereo: return "Preserve mono / stereo"
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        }
    }

    private func addArchiveRoot() {
        guard let folder = session.context.fileActions.chooseDirectory(prompt: "Choose Archive Root") else { return }
        archiveViewModel.addRoot(folder)
    }

    private func saveProjectVaultSettings(_ update: @escaping @Sendable (inout AppSettings) -> Void) -> Bool {
        let saved = session.persistSettings(update)
        if saved {
            archiveViewModel.applyProjectVaultSettingsChange()
        }
        return saved
    }

    private func openLoginSetting() {
        NotificationCenter.default.post(name: .hubOpenSettingsPane, object: HubSettingsPane.general)
    }

    private func openWAVConverter() {
        router.execute(.openTool(ToolFeatureID("wav-converter")))
        openWindow(id: "main")
        NSApp.activate()
    }
}

// MARK: - Settings rows

/// One grouped-form row: label (+ optional one-line description) on the left,
/// control flush right. Rows bring their own padding; the section card has none.
private struct SettingsRow<Control: View>: View {
    private let label: String
    private let description: String?
    private let control: Control

    init(_ label: String, description: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(HubDesignSystem.Typography.body().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                if let description {
                    Text(description)
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: HubDesignSystem.Spacing.controlGap)
            control
        }
        .padding(.horizontal, HubDesignSystem.Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hairline between rows: inset on the left to the label's leading edge,
/// running to the card's right edge. No separator after the last row.
private struct SettingsRowDivider: View {
    var body: some View {
        HubDesignSystem.Palette.separator
            .frame(height: 1)
            .padding(.leading, HubDesignSystem.Spacing.cardPadding)
    }
}

// MARK: - Settings section

private enum SettingsSectionImportance {
    case high
    case medium
    case low
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var importance: SettingsSectionImportance = .high
    var footer: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        importance: SettingsSectionImportance = .high,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.importance = importance
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
            .hubSurface(.panel, state: sectionIntent, cornerRadius: HubDesignSystem.Radius.popover)

            if let footer {
                Text(footer)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sectionIntent: HubDesignSystem.ControlState {
        switch importance {
        case .high, .medium, .low:
            return .normal
        }
    }
}
