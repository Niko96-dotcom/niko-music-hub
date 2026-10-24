import Foundation

/// A single entry in the quick-access menu allowlist.
/// Labels and system images are sourced from `ToolMetadata` where a registered
/// tool feature exists; a literal fallback is used for non-tool commands.
public struct QuickAccessEntry: Identifiable, Hashable, Sendable {
    /// Stable string identity. For tool entries this equals the `ToolFeatureID.rawValue`;
    /// for non-tool commands a human-readable slug is used (e.g. "output-inbox").
    public let id: String
    public let label: String
    public let systemImage: String
    public let command: QuickAccessCommand

    public init(id: String, label: String, systemImage: String, command: QuickAccessCommand) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.command = command
    }
}

public extension QuickAccessEntry {
    /// Curated extra-menu allowlist in display order: Archive Browser, then
    /// production tools, then Output Inbox. Settings is omitted (⌘,).
    /// The resolver filters this list against the live ToolRegistry before use.
    static let allowlist: [QuickAccessEntry] = [
        QuickAccessEntry(
            id: ToolFeatureID.archiveBrowser.rawValue,
            label: "Archive Browser",
            systemImage: "music.note.list",
            command: .openTool(.archiveBrowser)
        ),
        QuickAccessEntry(
            id: ToolFeatureID.audioRecorder.rawValue,
            label: "Audio Recorder",
            systemImage: "waveform.circle",
            command: .openTool(.audioRecorder)
        ),
        QuickAccessEntry(
            id: ToolFeatureID.wavConverter.rawValue,
            label: "WAV Converter",
            systemImage: "arrow.triangle.2.circlepath",
            command: .openTool(.wavConverter)
        ),
        QuickAccessEntry(
            id: ToolFeatureID.bpmTapper.rawValue,
            label: "BPM Tapper",
            systemImage: "metronome",
            command: .openTool(.bpmTapper)
        ),
        QuickAccessEntry(
            id: ToolFeatureID.downloader.rawValue,
            label: "Downloader",
            systemImage: "arrow.down.circle",
            command: .openTool(.downloader)
        ),
        QuickAccessEntry(
            id: ToolFeatureID.stemSeparation.rawValue,
            label: "Stem Separation",
            systemImage: "waveform.path",
            command: .openTool(.stemSeparation)
        ),
        QuickAccessEntry(
            id: "output-inbox",
            label: "Output Inbox",
            systemImage: "tray.and.arrow.down",
            command: .revealOutputInbox
        ),
    ]
}
