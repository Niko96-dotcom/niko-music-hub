import Foundation

/// Snapshot of yt-dlp, FFmpeg, and demucs-mlx health for the sidebar strip (NMH-010).
public struct HelperToolsHealthStripModel: Equatable, Sendable {
    public let items: [HelperToolsHealthItem]

    public init(items: [HelperToolsHealthItem]) {
        self.items = items
    }

    public var anyNeedsSetup: Bool {
        items.contains(where: \.needsSetup)
    }

    public static func make(
        ytDlp: HelperToolsHealthItem.State,
        ffmpeg: HelperToolsHealthItem.State,
        demucsMLX: HelperToolsHealthItem.State
    ) -> HelperToolsHealthStripModel {
        HelperToolsHealthStripModel(items: [
            HelperToolsHealthItem(label: "yt-dlp", state: ytDlp),
            HelperToolsHealthItem(label: "FFmpeg", state: ffmpeg),
            HelperToolsHealthItem(label: "demucs-mlx", state: demucsMLX),
        ])
    }

    public static let checking = make(ytDlp: .checking, ffmpeg: .checking, demucsMLX: .checking)
}

public struct HelperToolsHealthItem: Equatable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let state: State

    public init(label: String, state: State) {
        self.label = label
        self.state = state
    }

    public var needsSetup: Bool { state.needsSetup }

    public enum State: Equatable, Sendable {
        case checking
        case available(version: String)
        case missing
        case outdated(current: String, minimum: String)
        case unusable(message: String)

        public var needsSetup: Bool {
            switch self {
            case .missing, .outdated, .unusable:
                return true
            case .checking, .available:
                return false
            }
        }

        public var isWarning: Bool {
            if case .outdated = self { return true }
            return false
        }

        public var isError: Bool {
            switch self {
            case .missing, .unusable:
                return true
            case .checking, .available, .outdated:
                return false
            }
        }

        public var displayText: String {
            switch self {
            case .checking:
                return "Checking"
            case .available:
                return "Ready"
            case .missing:
                return "Missing"
            case .outdated:
                return "Update needed"
            case .unusable:
                return "Needs setup"
            }
        }
    }
}
