import AppCore
import FeatureArchiveBrowser
import SwiftUI

struct SettingsView: View {
    let context: ToolContext
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel

    @State private var settings: AppSettings = .default
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var saveError: String?

    private let recordingDurationChoices = [15, 30, 45, 60, 90, 120]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                SettingsSection(title: "General", footer: "Opens Niko Music Hub when you sign in to this Mac.") {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            setLaunchAtLogin(enabled)
                        }
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }

                SettingsSection(
                    title: "Output",
                    footer: "Converted audio, recordings, and downloads land here and appear in the Output Inbox."
                ) {
                    pathRow(
                        label: "Output folder",
                        path: settings.outputFolder.url.path
                    )
                    HStack(spacing: 8) {
                        Button("Choose Folder…") { chooseOutputFolder() }
                            .buttonStyle(.bordered)
                        Button("Reveal in Finder") {
                            context.fileActions.revealInFinder(settings.outputFolder.url)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingsSection(
                    title: "Cubase archive",
                    footer: "Read-only scan roots. The hub never renames, moves, or deletes files under these folders."
                ) {
                    archiveRootsSection
                }

                SettingsSection(
                    title: "Audio conversion",
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

                SettingsSection(title: "Recording", footer: "Maximum length for system-audio capture sessions.") {
                    Picker("Max duration", selection: maxRecordingBinding) {
                        ForEach(recordingDurationChoices, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                SettingsSection(
                    title: "Privacy & recording",
                    footer: "Only the Audio Recorder needs this. Other tools do not use your microphone. After a local rebuild, macOS may ask again until you allow the new app signature."
                ) {
                    Text("Enable Niko Music Hub under Screen & System Audio Recording so Recorder can capture Mac output to a WAV in your output folder.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Audio Recording Settings") {
                        SystemPrivacySettings.openSystemAudioRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                SettingsSection(
                    title: "Helper tools",
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

                SettingsSection(title: "About") {
                    LabeledContent("App") {
                        Text("Niko Music Hub")
                    }
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        LabeledContent("Version") {
                            Text(version)
                        }
                    }
                    Text("Local-first recall for Cubase archives plus outside-Cubase utilities. Archive browsing stays read-only toward your music folders.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let saveError {
                    Text(saveError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 56)
            .frame(minWidth: 320, idealWidth: 640, maxWidth: 720, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refresh() }
    }

    @ViewBuilder
    private var archiveRootsSection: some View {
        if archiveViewModel.roots.isEmpty {
            Text("No archive roots yet. Add the folder that contains your Cubase song folders.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(archiveViewModel.roots, id: \.path) { root in
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(root.lastPathComponent.isEmpty ? "Archive Root" : root.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                        Text(root.path)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("Remove") {
                        archiveViewModel.removeRoot(root)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        if archiveViewModel.roots.isEmpty {
            Button("Add Root…", action: addArchiveRoot)
                .buttonStyle(.borderedProminent)
        } else {
            Button("Add Root…", action: addArchiveRoot)
                .buttonStyle(.bordered)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Settings", systemImage: "gearshape")
                .font(.system(size: 16, weight: .semibold))
            Text("Hub-wide preferences for startup, output, archive roots, and helper tools.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .font(.system(size: 12, weight: .medium))
            Text(path)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func helperPathRow(
        label: String,
        url: URL?,
        prompt: String,
        onSet: @escaping (URL?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            if let path = url?.path {
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Auto-detect")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Browse…") {
                    guard let chosen = context.fileActions.chooseExecutable(prompt: prompt) else { return }
                    onSet(chosen)
                }
                .buttonStyle(.bordered)
                if url != nil {
                    Button("Clear") {
                        onSet(nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func channelModeLabel(_ mode: AudioChannelMode) -> String {
        switch mode {
        case .preserveMonoStereo: return "Preserve mono / stereo"
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        }
    }

    private func refresh() {
        settings = (try? context.settingsStore.loadSettings()) ?? .default
        launchAtLogin = context.launchAtLogin.isEnabled()
        launchAtLoginError = nil
        saveError = nil
    }

    private func persistSettings() {
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
        guard let folder = context.fileActions.chooseOutputFolder() else { return }
        settings.outputFolder = StoredFolderLocation(url: folder)
        persistSettings()
    }

    private func addArchiveRoot() {
        guard let folder = context.fileActions.chooseDirectory(prompt: "Choose Archive Root") else { return }
        archiveViewModel.addRoot(folder)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
