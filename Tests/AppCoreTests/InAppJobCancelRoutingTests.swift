@testable import AppCore
import FeatureArchiveBrowser
import XCTest

/// Esc / ⌘. routing (NMH-009) over the shell job list. The jobs are built as their
/// tools build them, and the panes are the tools' metadata, so these cases pin the
/// same results as the ID-based routing they replaced.
@MainActor
final class InAppJobCancelRoutingTests: XCTestCase {
    func testEscapeCancelsStemJobWhileStemPaneIsSelected() {
        let jobs = InAppJobCancelRouting.escapeJobs(selectedTool: Panes.stems, in: [stemJob()])

        XCTAssertEqual(jobs.map(\.id), [stemJob().id])
    }

    func testEscapeLeavesStemJobAloneOnOtherPanes() {
        for pane in [Panes.downloader, Panes.archive, Panes.bpm, Panes.converter] {
            XCTAssertEqual(
                InAppJobCancelRouting.escapeJobs(selectedTool: pane, in: [stemJob()]),
                [],
                "Esc on \(pane.id) must not cancel a stem separation"
            )
        }
        XCTAssertEqual(InAppJobCancelRouting.escapeJobs(selectedTool: nil, in: [stemJob()]), [])
    }

    func testEscapeOnStemPaneOnlyCancelsStemJobs() {
        XCTAssertEqual(
            InAppJobCancelRouting.escapeJobs(selectedTool: Panes.stems, in: [downloadJob(), vaultJob()]),
            []
        )
        XCTAssertEqual(
            InAppJobCancelRouting.escapeJobs(selectedTool: Panes.stems, in: [downloadJob(), vaultJob(), stemJob()])
                .map(\.id),
            [stemJob().id]
        )
    }

    func testCommandPeriodCancelsStemJob() {
        XCTAssertEqual(InAppJobCancelRouting.commandPeriodJobs(in: [stemJob()]).map(\.id), [stemJob().id])
        XCTAssertEqual(InAppJobCancelRouting.commandPeriodJobs(in: [vaultJob(), stemJob()]).map(\.id), [stemJob().id])
        XCTAssertEqual(
            InAppJobCancelRouting.commandPeriodJobs(in: [stemJob(), downloadJob()]).map(\.id),
            [downloadJob().id]
        )
    }

    func testEscapeCancelsConversionWhileConverterPaneIsSelected() {
        XCTAssertEqual(
            InAppJobCancelRouting.escapeJobs(selectedTool: Panes.converter, in: [converterJob()]).map(\.id),
            [converterJob().id]
        )
    }

    func testEscapeOnConverterPaneIgnoresOtherJobs() {
        XCTAssertEqual(InAppJobCancelRouting.escapeJobs(selectedTool: Panes.converter, in: [vaultJob()]), [])
        XCTAssertEqual(InAppJobCancelRouting.escapeJobs(selectedTool: Panes.converter, in: [stemJob()]), [])
    }

    func testCommandPeriodPrefersConversionOverVault() {
        XCTAssertEqual(InAppJobCancelRouting.commandPeriodJobs(in: [converterJob()]).map(\.id), [converterJob().id])
        XCTAssertEqual(
            InAppJobCancelRouting.commandPeriodJobs(in: [converterJob(), vaultJob()]).map(\.id),
            [converterJob().id]
        )
        XCTAssertEqual(
            InAppJobCancelRouting.commandPeriodJobs(in: [downloadJob(), converterJob()]).map(\.id),
            [downloadJob().id]
        )
    }

    /// The ⌘. order: downloads, stem separations, the conversion, the Vault transfer, the scan.
    func testCommandPeriodOrderAcrossEveryTarget() {
        var jobs = [scanJob(), vaultJob(), converterJob(), stemJob(), downloadJob(), downloadJob(id: "download-2")]
        for expected in [["download", "download-2"], [stemJob().id], [converterJob().id], [vaultJob().id], [scanJob().id]] {
            let cancelled = InAppJobCancelRouting.commandPeriodJobs(in: jobs).map(\.id)
            XCTAssertEqual(Set(cancelled), Set(expected))
            jobs.removeAll { cancelled.contains($0.id) }
        }
        XCTAssertEqual(InAppJobCancelRouting.commandPeriodJobs(in: jobs), [])
    }

    func testArchivePaneKeepsEscapeWhileShellWorkRuns() {
        XCTAssertEqual(InAppJobCancelRouting.escapeJobs(selectedTool: Panes.archive, in: [vaultJob(), scanJob()]), [])
    }

    func testPaneThatDoesNotHandleEscapeCancelsTheVaultTransferBeforeTheScan() {
        for pane in [Panes.bpm, Panes.recorder, nil] {
            XCTAssertEqual(
                InAppJobCancelRouting.escapeJobs(selectedTool: pane, in: [scanJob(), vaultJob(), downloadJob()])
                    .map(\.id),
                [vaultJob().id]
            )
            XCTAssertEqual(
                InAppJobCancelRouting.escapeJobs(selectedTool: pane, in: [scanJob(), converterJob()]).map(\.id),
                [scanJob().id]
            )
        }
    }

    func testIdleDownloaderPaneKeepsEscapeWhileShellWorkRuns() {
        XCTAssertEqual(InAppJobCancelRouting.escapeJobs(selectedTool: Panes.downloader, in: [vaultJob(), scanJob()]), [])
    }

    func testJobWithoutTargetIsNeverCancelledByTheKeys() {
        let sample = ShellJobStatus(id: "sample", title: "Sample Job", activityVerb: "Running", sourceToolID: "dev-tool")
        let devPane = ToolMetadata(id: "dev-tool", displayName: "Dev", shortLabel: "Dev", systemImage: "hammer")
        XCTAssertEqual(InAppJobCancelRouting.commandPeriodJobs(in: [sample]), [])
        XCTAssertEqual(InAppJobCancelRouting.escapeJobs(selectedTool: devPane, in: [sample]), [])
    }

    func testEscapeRoutesCancelThroughShellJobCenterToJobRunner() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let job = runner.enqueue(
            title: "YouTube to Stems: youtu.be",
            sourceToolID: .stemSeparation,
            activityVerb: "Separating",
            cancelTarget: .stemSeparation
        ) { _ in
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        try await waitUntil { center.jobs.contains { $0.id == job.id.uuidString } }

        let routed = InAppJobCancelRouting.escapeJobs(selectedTool: Panes.stems, in: center.jobs)
        XCTAssertEqual(routed.map(\.id), [job.id.uuidString])
        for status in routed {
            center.cancel(id: status.cancelActionID ?? status.id)
        }

        XCTAssertEqual(runner.job(id: job.id)?.state, .canceled)
        try await waitUntil { center.jobs.isEmpty }
    }

    /// The real archive feature keeps Esc; the panes below stand in for the other tools
    /// as their features declare them (their modules are not visible to AppCoreTests).
    func testArchiveFeatureDeclaresThatItsPaneHandlesEscape() {
        let feature = ArchiveBrowserFeature(viewModel: ArchiveBrowserViewModel(context: ToolContext.smokeTest()))
        XCTAssertTrue(feature.metadata.handlesEscape)
        XCTAssertEqual(feature.metadata, Panes.archive)
    }

    private enum Panes {
        static let archive = ToolMetadata(
            id: .archiveBrowser,
            displayName: "Archive Browser",
            shortLabel: "Archive",
            systemImage: "music.note.list",
            section: .library,
            handlesEscape: true
        )
        static let downloader = pane(.downloader, handlesEscape: true)
        static let stems = pane(.stemSeparation, handlesEscape: true)
        static let converter = pane(.wavConverter, handlesEscape: true)
        static let bpm = pane(.bpmTapper, handlesEscape: false)
        static let recorder = pane(.audioRecorder, handlesEscape: false)

        private static func pane(_ id: ToolFeatureID, handlesEscape: Bool) -> ToolMetadata {
            ToolMetadata(id: id, displayName: id.rawValue, shortLabel: id.rawValue, systemImage: "hammer",
                         handlesEscape: handlesEscape)
        }
    }

    private func stemJob() -> ShellJobStatus {
        ShellJobStatus(
            id: "8D8E4C0C-5A55-4E36-9A1B-000000000001",
            title: "Song",
            percent: 0.3,
            cancelActionID: "8D8E4C0C-5A55-4E36-9A1B-000000000001",
            activityVerb: "Separating",
            sourceToolID: .stemSeparation,
            cancelTarget: .stemSeparation
        )
    }

    private func downloadJob(id: String = "download") -> ShellJobStatus {
        ShellJobStatus(id: id, title: "Track", sourceToolID: .downloader, cancelTarget: .download)
    }

    private func converterJob() -> ShellJobStatus {
        ShellJobStatus(
            id: ShellJobExtraSourceID.converter,
            title: "a.mp3",
            percent: 0.4,
            cancelActionID: ShellJobExtraSourceID.converter,
            activityVerb: "Converting",
            sourceToolID: .wavConverter,
            cancelTarget: .conversion
        )
    }

    private func vaultJob() -> ShellJobStatus {
        ShellJobStatusCopy.vaultTransferStatus(songName: "Song", progress: nil)
    }

    private func scanJob() -> ShellJobStatus {
        ShellJobStatusCopy.archiveScanStatus
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
