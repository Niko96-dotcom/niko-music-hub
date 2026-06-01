import Foundation

public struct MusicRoot: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let url: URL

    public init(url: URL) {
        self.url = url.standardizedFileURL
        self.id = self.url.path
    }
}
