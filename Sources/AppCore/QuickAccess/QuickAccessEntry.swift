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
    /// Curated production-tool allowlist in display order (per D-01, CONTEXT.md).
    /// Labels and system images are sourced from ToolMetadata for tool entries.
    /// The resolver filters this list against the live ToolRegistry before use.
    static let allowlist: [QuickAccessEntry] = [
        QuickAccessEntry(
            id: "audio-recorder",
            label: "Audio Recorder",
            systemImage: "waveform.circle",
            command: .openTool("audio-recorder")
        ),
        QuickAccessEntry(
            id: "wav-converter",
            label: "WAV Converter",
            systemImage: "arrow.triangle.2.circlepath",
            command: .openTool("wav-converter")
        ),
        QuickAccessEntry(
            id: "bpm-tapper",
            label: "BPM Tapper",
            systemImage: "metronome",
            command: .openTool("bpm-tapper")
        ),
        QuickAccessEntry(
            id: "downloader",
            label: "Downloader",
            systemImage: "arrow.down.circle",
            command: .openTool("downloader")
        ),
        QuickAccessEntry(
            id: "stem-separation",
            label: "Stem Separation",
            systemImage: "waveform.path",
            command: .openTool("stem-separation")
        ),
        QuickAccessEntry(
            id: "output-inbox",
            label: "Output Inbox",
            systemImage: "tray.and.arrow.down",
            command: .revealOutputInbox
        ),
    ]
}
