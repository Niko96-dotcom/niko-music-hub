import Foundation

public protocol JobRunning: Sendable {
    func listJobs() -> [Job]

    func job(id: Job.ID) -> Job?

    @discardableResult
    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job

    func cancelJob(id: Job.ID)
}
