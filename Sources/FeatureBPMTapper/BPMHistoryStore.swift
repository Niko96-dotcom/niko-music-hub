import Foundation

public struct BPMHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var bpm: Double
    public var rawTappedBPM: Double
    public var adjustment: BPMAdjustment
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        bpm: Double,
        rawTappedBPM: Double,
        adjustment: BPMAdjustment,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.bpm = bpm
        self.rawTappedBPM = rawTappedBPM
        self.adjustment = adjustment
        self.timestamp = timestamp
    }
}

public protocol BPMHistoryStore: Sendable {
    func listEntries() throws -> [BPMHistoryEntry]
    func addEntry(_ entry: BPMHistoryEntry) throws
    func clearEntries() throws
}
