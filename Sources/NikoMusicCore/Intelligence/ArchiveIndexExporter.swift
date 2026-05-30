import Foundation

public struct ArchiveIndexExport: Equatable, Sendable, Codable {
    public let exportedAt: Date
    public let roots: [String]
    public let songCount: Int
    public let songs: [Song]

    public init(exportedAt: Date = Date(), roots: [URL], songs: [Song]) {
        self.exportedAt = exportedAt
        self.roots = roots.map { $0.standardizedFileURL.path }
        self.songCount = songs.count
        self.songs = songs
    }
}

public enum ArchiveIndexExporter {
    public static func exportJSON(roots: [URL], songs: [Song], encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = ArchiveIndexExport(roots: roots, songs: songs)
        return try encoder.encode(payload)
    }
}
