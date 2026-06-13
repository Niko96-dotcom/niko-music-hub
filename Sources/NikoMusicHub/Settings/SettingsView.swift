import AppCore
import FeatureArchiveBrowser
import SwiftUI

struct SettingsView: View {
    let context: ToolContext
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel

    @State private var settings: AppSettings = .default
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var settingsLoadError: String?
    @State private var saveError: String?

    private let recordingDurationChoices = [15, 30, 45, 60, 90, 120]

    var body: some View {
        ScrollView {
            VStack(spacing: HubDesignSystem.Spacing.section) {
                header
                settingsLoadErrorBanner

                SettingsSection(
                    title: "General",
                    importance: .high,
                    footer: "Opens Niko Music Hub when you sign in to this Mac."
                ) {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
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
                    title: "Cubase archive",
                    importance: .high,
                    footer: "Read-only scan roots. The hub never renames, moves, or deletes files under these folders."
                ) {
                    archiveRootsSection
                }

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
                            Text("\(minutes) minutes").tag(minutes)
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
                        .foregroundStyle(.secondary)
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
                        persistSettings()
                    }
                    helperPathRow(label: "ffprobe", url: settings.helperTools.ffprobe, prompt: "Choose ffprobe") { url in
                        settings.helperTools.ffprobe = url
                        persistSettings()
                    }
                    helperPathRow(label: "yt-dlp", url: settings.helperTools.ytDlp, prompt: "Choose yt-dlp") { url in
                        settings.helperTools.ytDlp = url
                        persistSettings()
                    }
                }

                SettingsSection(title: "About", importance: .low) {
                    LabeledContent("App") {
                        Text("Niko Music Hub")
                    }
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        LabeledContent("Version") {
                            Text(version)
                        }
                    }
                    Text("Local-first recall for Cubase archives plus outside-Cubase utilities. Archive browsing stays read-only toward your music folders.")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                saveErrorBanner
            }
            .hubGlassGroup(spacing: HubDesignSystem.Spacing.section)
            .hubToolContentPadding()
            .frame(maxWidth: HubToolLayout.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear { refresh() }
    }

    @ViewBuilder
    private var archiveRootsSection: some View {
        if archiveViewModel.roots.isEmpty {
            Text("No archive roots yet. Add the folder that contains your Cubase song folders.")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(.secondary)
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
            help: "Choose a Cubase projects folder to scan",
            action: addArchiveRoot
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
            Text("Settings")
                .font(HubDesignSystem.Typography.screenTitle())
            Text("Hub-wide preferences for startup, output, and tools.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var settingsLoadErrorBanner: some View {
        if let settingsLoadError {
            Label(settingsLoadError, systemImage: "exclamationmark.triangle.fill")
                .font(HubDesignSystem.Typography.bodySmall())
                .foregroundStyle(HubDesignSystem.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .hubLiquidCard(cornerRadius: HubDesignSystem.Radius.row, intent: .warning)
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
                .padding(12)
                .hubLiquidCard(cornerRadius: HubDesignSystem.Radius.row, intent: .error)
        }
    }

    private var maxRecordingBinding: Binding<Int> {
        Binding(
            get: { settings.maxRecordingDurationMinutes },
            set: { newValue in
                settings.maxRecordingDurationMinutes = newValue
                persistSettings()
            }
        )
    }

    private func pathRow(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HubDesignSystem.Typography.caption().weight(.medium))
            Text(path)
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(10)
        .hubGlassField(minHeight: 48)
    }

    private func archiveRootRow(_ root: URL) -> some View {
        HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(HubDesignSystem.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(root.lastPathComponent.isEmpty ? "Archive Root" : root.lastPathComponent)
                    .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
                Text(root.path)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(.secondary)
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
        .hubLiquidCard(cornerRadius: HubDesignSystem.Radius.row)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button("Choose…") {
                    guard let chosen = context.fileActions.chooseExecutable(prompt: prompt) else { return }
                    onSet(chosen)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(settingsLoadError != nil)

                if url != nil {
                    Button {
                        onSet(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Use auto-detect for \(label)")
                    .disabled(settingsLoadError != nil)
                }
            }
            .padding(8)
            .hubGlassField(minHeight: 40)
        }
    }

    private func inlineWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(HubDesignSystem.Typography.bodySmall())
            .foregroundStyle(HubDesignSystem.Colors.warning)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .hubLiquidCard(cornerRadius: HubDesignSystem.Radius.row, intent: .warning)
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
            settingsLoadError = nil
        } catch {
            settings = .default
            settingsLoadError = "Could not load settings. Existing settings were left untouched: \(error.localizedDescription)"
            context.diagnostics.log(.error, "Settings load failed: \(error)")
        }
        launchAtLogin = context.launchAtLogin.isEnabled()
        launchAtLoginError = nil
        saveError = nil
    }

    private func persistSettings() {
        guard settingsLoadError == nil else {
            saveError = "Settings were not saved because the current settings could not be loaded."
            return
        }
        do {
            try context.settingsStore.saveSettings(settings)
            saveError = nil
        } catch {
            saveError = "Could not save settings."
            context.diagnostics.log(.error, "Settings save failed")
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
        settings.outputFolder = StoredFolderLocation(url: folder)
        persistSettings()
    }

    private func addArchiveRoot() {
        guard let folder = context.fileActions.chooseDirectory(prompt: "Choose Archive Root") else { return }
        archiveViewModel.addRoot(folder)
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
        VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.cardGap) {
            Text(title)
                .font(HubDesignSystem.Typography.sectionTitle())
                .foregroundStyle(importance == .low ? .secondary : .primary)

            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.controlGap) {
                content
            }
            .padding(sectionPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubLiquidCard(cornerRadius: HubDesignSystem.Radius.card, intent: sectionIntent)

            if let footer {
                Text(footer)
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sectionIntent: HubLiquidSurfaceIntent {
        switch importance {
        case .high, .medium, .low:
            return .normal
        }
    }

    private var sectionPadding: CGFloat {
        switch importance {
        case .high, .medium:
            return 12
        case .low:
            return 10
        }
    }
}
