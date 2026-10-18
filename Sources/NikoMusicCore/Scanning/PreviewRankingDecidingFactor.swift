import Foundation

/// Which comparison step separated two preview candidates (after scoring).
public enum PreviewRankingDecidingFactor: String, Sendable, Equatable, Codable {
    case songSuitability
    case deliveryLocation
    case score
    case productionMaturity
    case version
    case titleMatch
    case extensionFormat
    case duration
    case recency
    case filename
}
