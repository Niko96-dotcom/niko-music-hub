@testable import AppCore
import XCTest

/// Esc / ⌘. routing (NMH-009) over the shell job list.
@MainActor
final class InAppJobCancelRoutingTests: XCTestCase {
    private let stemToolID = ToolFeatureID("stem-separation")

    func testEscapeCancelsStemJobWhileStemPaneIsSelected() {
        let activity = InAppJobActivity(jobs: [stemJob()])

        let target = InAppJobCancelRouting.escapeTarget(selectedToolID: stemToolID, activity)

        XCTAssertEqual(target, .stemSeparation)
        XCTAssertEqual(activity.jobs(for: .stemSeparation).map(\.id), [stemJob().id])
    }

    func testEscapeLeavesStemJobAloneOnOtherPanes() {
        let activity = InAppJobActivity(jobs: [stemJob()])

        for toolID in ["downloader", "archive-browser", "bpm-tapper", "wav-converter"] {
            XCTAssertNil(
                InAppJobCancelRouting.escapeTarget(selectedToolID: ToolFeatureID(toolID), activity),
                "Esc on \(toolID) must not cancel a stem separation"
            )
        }
        XCTAssertNil(InAppJobCancelRouting.escapeTarget(selectedToolID: nil, activity))
    }

    func testEscapeOnStemPaneOnlyCancelsStemJobs() {
        let activity = InAppJobActivity(jobs: [downloadJob(), vaultJob()])

        XCTAssertNil(InAppJobCancelRouting.escapeTarget(selectedToolID: stemToolID, activity))
        XCTAssertEqual(
            InAppJobCancelRouting.escapeTarget(
                selectedToolID: stemToolID,
                InAppJobActivity(jobs: [downloadJob(), vaultJob(), stemJob()])
            ),
            .stemSeparation
        )
    }

    func testCommandPeriodCancelsStemJob() {
        XCTAssertEqual(InAppJobCancelRouting.foremost(InAppJobActivity(jobs: [stemJob()])), .stemSeparation)
        XCTAssertEqual(
            InAppJobCancelRouting.foremost(InAppJobActivity(jobs: [vaultJob(), stemJob()])),
            .stemSeparation
        )
        XCTAssertEqual(
            InAppJobCancelRouting.foremost(InAppJobActivity(jobs: [stemJob(), downloadJob()])),
            .download
        )
    }

    func testEscapeRoutesCancelThroughShellJobCenterToJobRunner() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let job = runner.enqueue(title: "YouTube to Stems: youtu.be", sourceToolID: stemToolID) { _ in
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        try await waitUntil { center.jobs.contains { $0.id == job.id.uuidString } }

        let activity = InAppJobActivity(jobs: center.jobs)
        XCTAssertEqual(
            InAppJobCancelRouting.escapeTarget(selectedToolID: stemToolID, activity),
            .stemSeparation
        )
        for status in activity.jobs(for: .stemSeparation) {
            center.cancel(id: status.cancelActionID ?? status.id)
        }

        XCTAssertEqual(runner.job(id: job.id)?.state, .canceled)
        try await waitUntil { center.jobs.isEmpty }
    }

    private func stemJob() -> ShellJobStatus {
        ShellJobStatus(
            id: "8D8E4C0C-5A55-4E36-9A1B-000000000001",
            title: "Song",
            percent: 0.3,
            cancelActionID: "8D8E4C0C-5A55-4E36-9A1B-000000000001",
            activityVerb: "Separating",
            sourceToolID: stemToolID
        )
    }

    private func downloadJob() -> ShellJobStatus {
        ShellJobStatus(id: "download", title: "Track", sourceToolID: "downloader")
    }

    private func vaultJob() -> ShellJobStatus {
        ShellJobStatus(
            id: ShellJobExtraSourceID.vaultTransfer,
            title: "Song",
            cancelActionID: ShellJobExtraSourceID.vaultTransfer
        )
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}
