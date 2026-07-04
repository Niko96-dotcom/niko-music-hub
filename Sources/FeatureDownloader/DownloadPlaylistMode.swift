import Foundation

public enum DownloadPlaylistMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case single
    case playlist
    case channel

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .single: "Single video"
        case .playlist: "Playlist"
        case .channel: "Channel (limited)"
        }
    }

    public var maxEntries: Int? {
        switch self {
        case .single: 1
        case .playlist: 25
        case .channel: 10
        }
    }
}
