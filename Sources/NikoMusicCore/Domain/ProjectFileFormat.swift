import Foundation

/// The DAW is derived from the file, so existing archive snapshots need no migration.
public enum ProjectFileFormat: String, CaseIterable, Sendable, Codable {
    case cubase = "cpr"
    case abletonLive = "als"

    public init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }

    public var displayName: String {
        switch self {
        case .cubase: "Cubase"
        case .abletonLive: "Ableton Live"
        }
    }

    public var fileLabel: String { rawValue.uppercased() }
}
