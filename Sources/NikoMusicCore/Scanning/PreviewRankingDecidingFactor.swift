import Foundation

/// Which comparison step separated two preview candidates (after scoring).
public enum PreviewRankingDecidingFactor: String, Sendable, Equatable, Codable {
    case score
    case version
    case extensionFormat
    case duration
    case recency
    case filename
}
