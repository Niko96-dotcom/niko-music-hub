import Foundation

/// One recorded workflow status transition for a song (app-owned; feeds
/// stuck-time and per-stage analytics).
public struct WorkflowStatusChange: Equatable, Sendable, Codable {
    public let songID: String
    public let fromStatus: ProjectWorkflowStatus?
    public let toStatus: ProjectWorkflowStatus?
    public let changedAt: Date

    public init(
        songID: String,
        fromStatus: ProjectWorkflowStatus?,
        toStatus: ProjectWorkflowStatus?,
        changedAt: Date
    ) {
        self.songID = songID
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.changedAt = changedAt
    }
}
