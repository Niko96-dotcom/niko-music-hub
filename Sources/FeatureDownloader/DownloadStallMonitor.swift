import Foundation

public protocol DownloadStallClock: Sendable {
    var now: Date { get }
}

public struct SystemDownloadStallClock: DownloadStallClock {
    public init() {}

    public var now: Date { Date() }
}

/// What yt-dlp is doing, as far as its output tells us. The stall rule
/// depends on it: a download streams progress, but ffmpeg post-processing
/// (`--extract-audio`, merging, fixups) stays silent until it finishes.
public enum DownloadActivityPhase: Equatable, Sendable {
    case downloading
    /// `step` is yt-dlp's post-processor key, e.g. `ExtractAudio` or `Merger`.
    case postProcessing(step: String)

    static let postProcessPrefix = "NIKO_POSTPROCESS:"
    static let filePrefix = "NIKO_MUSIC_HUB_FILE:"

    /// yt-dlp post-processor keys (`PostProcessor.pp_key()`, yt-dlp 2026.08).
    /// Non-quiet runs print them as `[Key] …`; they only matter as a fallback,
    /// because `--print` puts yt-dlp in quiet mode and the post-process
    /// progress template (`NIKO_POSTPROCESS:`) is what normally arrives.
    static let postProcessorKeys: Set<String> = [
        "Concat", "CopyStream", "EmbedSubtitle", "EmbedThumbnail", "Exec", "ExecAfterDownload",
        "ExtractAudio", "FixupDuplicateMoov", "FixupDuration", "FixupM3u8", "FixupM4a",
        "FixupStretched", "FixupTimestamp", "Merger", "Metadata", "MetadataFromField",
        "MetadataFromTitle", "MetadataParser", "ModifyChapters", "MoveFiles", "SplitChapters",
        "SponsorBlock", "SubtitlesConvertor", "ThumbnailsConvertor", "VideoConvertor",
        "VideoRemuxer", "XAttrMetadata",
    ]

    /// The phase a yt-dlp output line announces, or nil when the line says
    /// nothing about the phase (warnings, extractor chatter).
    static func announced(by line: String) -> DownloadActivityPhase? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(postProcessPrefix) {
            // `NIKO_POSTPROCESS:<status>:<Key>`
            let fields = trimmed.dropFirst(postProcessPrefix.count).split(separator: ":", maxSplits: 1)
            let step = fields.count == 2 ? String(fields[1]) : ""
            return .postProcessing(step: step)
        }
        if trimmed.hasPrefix(DownloaderProgressParsing.nikoProgressPrefix)
            || trimmed.hasPrefix("[download]")
            || trimmed.hasPrefix(filePrefix) {
            // A progress line, a playlist's next item, or a finished file:
            // anything after it is download work again.
            return .downloading
        }
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            if postProcessorKeys.contains(key) {
                return .postProcessing(step: key)
            }
        }
        return nil
    }

    /// The phase announced by the newest phase-bearing line.
    static func latest(in lines: [String]) -> DownloadActivityPhase? {
        for line in lines.reversed() {
            if let phase = announced(by: line) { return phase }
        }
        return nil
    }

    /// User-facing status for the phase; nil while downloading.
    public var statusMessage: String? {
        guard case let .postProcessing(step) = self else { return nil }
        return DownloaderCopy.postProcessingStatus(step: step)
    }
}

public final class DownloadStallMonitor: @unchecked Sendable {
    public static let stallWindowSeconds: TimeInterval = 120
    /// ffmpeg reports nothing until it finishes, and an hour-long mix can take
    /// minutes to convert. A hung ffmpeg still ends here.
    public static let postProcessingStallWindowSeconds: TimeInterval = 30 * 60
    public static let slowHintSeconds: TimeInterval = 30
    public static let stallErrorMessage = "Download stalled — no progress for 2 minutes"
    public static let postProcessingStallErrorMessage = "Conversion stalled — no progress for 30 minutes"
    public static let slowHintMessage = "Still working. This download has not reported new data."

    private let clock: any DownloadStallClock
    private let lock = NSLock()
    private var lastActivity: Date
    private var currentPhase: DownloadActivityPhase = .downloading

    public init(clock: any DownloadStallClock = SystemDownloadStallClock()) {
        self.clock = clock
        self.lastActivity = clock.now
    }

    public var phase: DownloadActivityPhase {
        lock.withLock { currentPhase }
    }

    public func recordActivity() {
        lock.withLock {
            lastActivity = clock.now
        }
    }

    /// Records output and moves to the phase the line announces, if any.
    public func recordActivity(line: String) {
        recordActivity(phase: DownloadActivityPhase.announced(by: line))
    }

    /// Records output; a nil phase keeps the current one.
    public func recordActivity(phase: DownloadActivityPhase?) {
        lock.withLock {
            lastActivity = clock.now
            if let phase { currentPhase = phase }
        }
    }

    public func checkStalled() -> Bool {
        stallFailureMessage() != nil
    }

    /// The failure message when the current phase has been silent past its
    /// window, else nil. Phase and silence are read together.
    public func stallFailureMessage() -> String? {
        lock.withLock {
            let downloading = currentPhase == .downloading
            let window = downloading ? Self.stallWindowSeconds : Self.postProcessingStallWindowSeconds
            guard clock.now.timeIntervalSince(lastActivity) >= window else { return nil }
            return downloading ? Self.stallErrorMessage : Self.postProcessingStallErrorMessage
        }
    }

    /// The "not reported new data" hint is download-only: silence is the
    /// normal state of post-processing, which shows its own status instead.
    public func checkSlowHint() -> Bool {
        lock.withLock {
            currentPhase == .downloading
                && clock.now.timeIntervalSince(lastActivity) >= Self.slowHintSeconds
        }
    }
}
