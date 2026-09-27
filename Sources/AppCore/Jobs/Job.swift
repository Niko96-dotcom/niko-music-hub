import Foundation

public enum JobState: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case canceled
}

public extension JobState {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .canceled:
            true
        case .queued, .running:
            false
        }
    }
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
    public var failureReason: JobFailureReason?
    public var logEntries: [JobLogEntry]
    public var outputFileURLs: [URL]
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
        failureReason: JobFailureReason? = nil,
        logEntries: [JobLogEntry] = [],
        outputFileURLs: [URL] = [],
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
        self.failureReason = failureReason
        self.logEntries = logEntries
        self.outputFileURLs = outputFileURLs
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// Stable typed failure reason for job recovery. Presentation text stays in
/// `message`; recovery decisions must read this field. Synthesized `Codable`
/// decodes a missing `failureReason` key as nil, preserving older snapshots.
public enum JobFailureReason: String, Codable, Sendable, CaseIterable {
    case helperUnavailable
    /// yt-dlp missing/outdated/unusable. Downloader-tool-specific: Stems
    /// demucs setup UI keys only on `helperUnavailable`, never on this case.
    case downloaderHelperUnavailable
    /// The run produced only verified pre-existing outputs (`--no-overwrites`
    /// skip). Informational already-exists presentation, not a failure alert.
    case downloadAlreadyExists
}

/// Thrown errors that carry a stable recovery reason. `JobRunner` saves the
/// reason while preserving `localizedDescription` separately in `Job.message`.
public protocol JobFailureReasonProviding: Error {
    var jobFailureReason: JobFailureReason? { get }
}
