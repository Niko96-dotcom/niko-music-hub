import AppCore
import FeatureArchiveBrowser
import NikoMusicCore
import SwiftUI

struct SettingsView: View {
    let context: ToolContext
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    @ObservedObject var appearanceController: AppAppearanceController

    @State private var settings: AppSettings = .default
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var settingsLoadError: String?
    @State private var saveError: String?
    @State private var helperPathError: String?

    private let recordingDurationChoices = RecordingDurationOptions.supportedMinutes

    var body: some View {
        HubToolPage {
            header
            settingsLoadErrorBanner

            SettingsSection(
                title: "General",
                importance: .high,
                footer: "Choose whether the hub follows macOS or stays in a fixed light or dark appearance."
            ) {
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    Text("Appearance")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    HubChoiceChips(
                        "Appearance",
                        selection: appearanceBinding,
                        choices: AppAppearance.allCases.map { .init($0, label: $0.label) }
                    )
                    .disabled(settingsLoadError != nil)
                }

                Toggle("Open at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(HubDesignSystem.Palette.accent)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    inlineWarning(launchAtLoginError)
                }
            }

            SettingsSection(
                title: "Output",
                importance: .high,
                footer: "Converted audio, recordings, and downloads land here and appear in the Output Inbox."
            ) {
                pathRow(
                    label: "Output folder",
                    path: settings.outputFolder.url.path
                )
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    HubLabeledButton(
                        icon: "folder.badge.gearshape",
                        label: "Choose Folder",
                        style: .secondary,
                        help: "Pick where exports and recordings are saved",
                        isEnabled: settingsLoadError == nil
                    ) {
                        chooseOutputFolder()
                    }
                    HubLabeledButton(
                        icon: "folder",
                        label: "Reveal in Finder",
                        style: .ghost,
                        help: "Show output folder in Finder"
                    ) {
                        context.fileActions.revealInFinder(settings.outputFolder.url)
                    }
                }
            }

            SettingsSection(
                title: "Music archive",
                importance: .high,
                footer: "Read-only scan roots. The hub never renames, moves, or deletes files under these folders."
            ) {
                archiveRootsSection
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan exclusions")
                        .font(HubDesignSystem.Typography.caption().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    TextField(
                        "",
                        text: scanExclusionBinding,
                        prompt: Text("backup, tmp, archive")
                            .foregroundColor(HubDesignSystem.Palette.textTertiary)
                    )
                    .textFieldStyle(.plain)
                    .font(HubDesignSystem.Typography.body())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
                    Text("Comma-separated folder-name terms to skip during scan.")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }
            }

            ProjectVaultSettingsView(
                context: context,
                settings: $settings,
                settingsAvailable: settingsLoadError == nil,
                onSave: saveProjectVaultSettings
            )

            SettingsSection(
                title: "Audio conversion",
                importance: .medium,
                footer: "Default WAV preset for the converter and recorder. You can override per batch in the WAV Converter."
            ) {
                LabeledContent("Sample rate") {
                    Text("\(settings.audioPreset.sampleRate) Hz")
                }
                LabeledContent("Bit depth") {
                    Text("\(settings.audioPreset.bitDepth)-bit")
                }
                LabeledContent("Channels") {
                    Text(channelModeLabel(settings.audioPreset.channelMode))
                }
            }

            SettingsSection(
                title: "Recording",
                importance: .medium,
                footer: "Maximum length for system-audio capture sessions."
            ) {
                Picker("Max duration", selection: maxRecordingBinding) {
                    ForEach(recordingDurationChoices, id: \.self) { minutes in
                        Text(RecordingDurationOptions.label(for: minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .disabled(settingsLoadError != nil)
                .frame(maxWidth: 280, alignment: .leading)
            }

            SettingsSection(
                title: "Privacy & recording",
                importance: .low,
                footer: "Only the Audio Recorder needs this. Other tools do not use your microphone. After a local rebuild, macOS may ask again until you allow the new app signature."
            ) {
                Text("Enable Niko Music Hub under Screen & System Audio Recording so Recorder can capture Mac output to a WAV in your output folder.")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HubLabeledButton(
                    icon: "lock.shield",
                    label: "Open System Settings",
                    style: .primary,
                    help: "Open Screen & System Audio Recording in System Settings"
                ) {
                    SystemPrivacySettings.openSystemAudioRecordingSettings()
                }
            }

            SettingsSection(
                title: "Helper tools",
                importance: .low,
                footer: "Optional paths when Homebrew installs are not on PATH. Status also appears in the tools sidebar."
            ) {
                helperPathRow(label: "FFmpeg", url: settings.helperTools.ffmpeg, prompt: "Choose FFmpeg") { url in
                    settings.helperTools.ffmpeg = url
                    persistSettings { $0.helperTools.ffmpeg = url }
                }
                helperPathRow(label: "ffprobe", url: settings.helperTools.ffprobe, prompt: "Choose ffprobe") { url in
                    settings.helperTools.ffprobe = url
                    persistSettings { $0.helperTools.ffprobe = url }
                }
                helperPathRow(label: "yt-dlp", url: settings.helperTools.ytDlp, prompt: "Choose yt-dlp") { url in
                    settings.helperTools.ytDlp = url
                    persistSettings { $0.helperTools.ytDlp = url }
                }
                helperPathRow(label: "demucs-mlx", url: settings.helperTools.demucsMlx, prompt: "Choose demucs-mlx") { url in
                    settings.helperTools.demucsMlx = url
                    persistSettings { $0.helperTools.demucsMlx = url }
                }
            }

            SettingsSection(title: "About", importance: .low) {
                let buildIdentity = AppBuildIdentity()
                LabeledContent("App") {
                    Text("Niko Music Hub")
                }
                if let version = buildIdentity.marketingVersion {
                    LabeledContent("Version") {
                        Text(version)
                    }
                }
                if let buildID = buildIdentity.buildID {
                    LabeledContent("Build") {
                        Text(buildID)
                            .textSelection(.enabled)
                    }
                }
                if let commit = buildIdentity.shortSourceCommit {
                    LabeledContent("Source") {
                        Text(commit)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }
                Text("Local-first recall for Cubase and Ableton archives plus production utilities. Archive browsing stays read-only toward your music folders.")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            saveErrorBanner
            helperPathErrorBanner
        }
        .onAppear { refresh() }
    }

    @ViewBuilder
    private var archiveRootsSection: some View {
        if archiveViewModel.roots.isEmpty {
            Text("No archive roots yet. Add the folder that contains your Cubase or Ableton song folders.")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(archiveViewModel.roots, id: \.path) { root in
                archiveRootRow(root)
            }
        }
        HubLabeledButton(
            icon: "folder.badge.plus",
            label: "Add Root",
            style: .secondary,
            help: "Choose a Cubase or Ableton projects folder to scan",
            action: addArchiveRoot
        )
    }

    private var header: some View {
        ToolHeaderBlock(
            title: "Settings",
            systemImage: "gearshape",
            statusText: "Hub-wide preferences for startup, output, and tools.",
            statusColor: HubDesignSystem.Palette.textSecondary
        )
    }

    @ViewBuilder
    private var settingsLoadErrorBanner: some View {
        if let settingsLoadError {
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
        if let saveError {
            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Colors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HubDesignSystem.Spacing.section)
                .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .error)
        }
    }

    @ViewBuilder
    private var helperPathErrorBanner: some View {
        if let helperPathError {
            Label(helperPathError, systemImage: "exclamationmark.triangle.fill")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HubDesignSystem.Spacing.section)
                .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
        }
    }

    private var maxRecordingBinding: Binding<Int> {
        Binding(
            get: { settings.maxRecordingDurationMinutes },
            set: { newValue in
                let normalized = RecordingDurationOptions.normalized(newValue)
                let previous = settings.maxRecordingDurationMinutes
                settings.maxRecordingDurationMinutes = normalized
                if !persistSettings({ $0.maxRecordingDurationMinutes = normalized }) {
                    settings.maxRecordingDurationMinutes = previous
                }
            }
        )
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { settings.appearance },
            set: { newValue in
                let previous = settings.appearance
                settings.appearance = newValue
                appearanceController.apply(newValue)
                if !persistSettings({ $0.appearance = newValue }) {
                    settings.appearance = previous
                    appearanceController.apply(previous)
                }
            }
        )
    }

    private var scanExclusionBinding: Binding<String> {
        Binding(
            get: { settings.scanExclusionTerms },
            set: { newValue in
                let previous = settings.scanExclusionTerms
                settings.scanExclusionTerms = newValue
                if !persistSettings({ $0.scanExclusionTerms = newValue }) {
                    settings.scanExclusionTerms = previous
                }
            }
        )
    }

    private func pathRow(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HubDesignSystem.Typography.caption().weight(.medium))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            Text(path)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(HubDesignSystem.Spacing.controlGap)
        .hubSurface(.field)
        .frame(minHeight: 48)
    }

    private func archiveRootRow(_ root: URL) -> some View {
        HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(HubDesignSystem.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(root.lastPathComponent.isEmpty ? "Archive Root" : root.lastPathComponent)
                    .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                Text(root.path)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            HubIconButton(
                systemImage: "trash",
                accessibilityLabel: "Remove archive root",
                help: "Remove \(root.lastPathComponent) from scan list",
                role: .destructive
            ) {
                archiveViewModel.removeRoot(root)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }

    private func helperPathRow(
        label: String,
        url: URL?,
        prompt: String,
        onSet: @escaping (URL?) -> Void
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                Text(url?.path ?? "Auto-detect")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HubLabeledButton(
                    icon: "ellipsis",
                    label: "Choose…",
                    style: .ghost,
                    isEnabled: settingsLoadError == nil
                ) {
                    guard let chosen = context.fileActions.chooseExecutable(prompt: prompt) else { return }
                    if let validationError = HelperExecutableValidation.validate(url: chosen) {
                        helperPathError = "\(label): \(validationError)"
                        return
                    }
                    helperPathError = nil
                    onSet(chosen)
                }

                if url != nil {
                    HubIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Use auto-detect for \(label)",
                        help: "Use auto-detect for \(label)",
                        isEnabled: settingsLoadError == nil
                    ) {
                        onSet(nil)
                    }
                }
            }
            .padding(8)
            .hubSurface(.field)
            .frame(minHeight: 40)
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

    private func refresh() {
        do {
            settings = try context.settingsStore.loadSettings()
            settings.maxRecordingDurationMinutes = RecordingDurationOptions.normalized(
                settings.maxRecordingDurationMinutes
            )
            settingsLoadError = nil
            appearanceController.apply(settings.appearance)
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
    private func persistSettings(_ update: @escaping @Sendable (inout AppSettings) -> Void) -> Bool {
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

    private func setLaunchAtLogin(_ enabled: Bool) {
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

    private func chooseOutputFolder() {
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

    private func addArchiveRoot() {
        guard let folder = context.fileActions.chooseDirectory(prompt: "Choose Archive Root") else { return }
        archiveViewModel.addRoot(folder)
    }

    private func saveProjectVaultSettings(_ update: @escaping @Sendable (inout AppSettings) -> Void) -> Bool {
        let saved = persistSettings(update)
        if saved {
            archiveViewModel.applyProjectVaultSettingsChange()
        }
        return saved
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

            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
                content
            }
            .padding(HubDesignSystem.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubSurface(.panel, state: sectionIntent, cornerRadius: HubDesignSystem.Radius.panel)

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
