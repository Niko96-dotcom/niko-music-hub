import Foundation

public enum JobState: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case canceled
}

public struct JobLogEntry: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var message: String
    public var createdAt: Date

    public init(id: UUID = UUID(), message: String, createdAt: Date = Date()) {
        self.id = id
        self.message = message
        self.createdAt = createdAt
    }
}

public struct Job: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var sourceToolID: ToolFeatureID
    public var title: String
    public var state: JobState
    public var progress: Double
    public var message: String
    public var logEntries: [JobLogEntry]
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: UUID = UUID(),
        sourceToolID: ToolFeatureID,
        title: String,
        state: JobState = .queued,
        progress: Double = 0,
        message: String = "",
        logEntries: [JobLogEntry] = [],
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.sourceToolID = sourceToolID
        self.title = title
        self.state = state
        self.progress = progress
        self.message = message
        self.logEntries = logEntries
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
