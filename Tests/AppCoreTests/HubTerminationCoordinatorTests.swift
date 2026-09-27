@testable import AppCore
import XCTest

/// ENG-04 / ADR-019: quit reads the job center, asks when work is running, cancels
/// every job on confirm and replies once the work has unwound or at a deadline.
@MainActor
final class HubTerminationCoordinatorTests: XCTestCase {
    func testNoRegisteredWorkTerminatesNow() {
        let center = ShellJobStatusCenter(jobRunner: JobRunner())
        // A background archive scan is shown in the jobs strip but is safe to cut off.
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.archiveScan,
            status: ShellJobStatus(
                id: ShellJobExtraSourceID.archiveScan,
                title: ShellJobStatusCopy.scanningArchive,
                blocksQuit: false
            )
        )
        let coordinator = HubTerminationCoordinator(jobStatusCenter: center)

        XCTAssertEqual(coordinator.decision(), .terminateNow)
    }

    func testRunningDownloadAsksAndNamesTheWork() throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let job = runner.enqueue(title: "Track Mix", sourceToolID: "downloader") { _ in
            try await Task.sleep(for: .seconds(30))
        }
        defer { runner.cancelJob(id: job.id) }
        let coordinator = HubTerminationCoordinator(jobStatusCenter: center)

        guard case .ask(let prompt) = coordinator.decision() else {
            return XCTFail("A running download must ask before quitting")
        }
        XCTAssertEqual(prompt.work.map(\.id), [job.id.uuidString])
        XCTAssertTrue(prompt.message.contains("Downloading “Track Mix”"), prompt.message)
        XCTAssertEqual(prompt.keepOpenButton, "Keep Music Hub Open")
        XCTAssertEqual(prompt.quitButton, "Stop and Quit")
    }

    func testVaultTransferNamesItsRecoveryCopy() throws {
        let center = ShellJobStatusCenter(jobRunner: JobRunner())
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.vaultTransfer,
            status: ShellJobStatus(
                id: ShellJobExtraSourceID.vaultTransfer,
                title: "Summer Song",
                activityVerb: "Transferring"
            )
        )
        let coordinator = HubTerminationCoordinator(jobStatusCenter: center)

        guard case .ask(let prompt) = coordinator.decision() else {
            return XCTFail("A Vault transfer must ask before quitting")
        }
        XCTAssertTrue(prompt.message.contains("Transferring “Summer Song”"), prompt.message)
        XCTAssertTrue(prompt.message.contains("recovery"), prompt.message)
    }

    func testConfirmCancelsEveryJobAndRepliesAfterRegistryDrains() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let unwound = Flag()
        let job = runner.enqueue(title: "Track Mix", sourceToolID: "downloader") { _ in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                // The cancel path still has cleanup to do after the job reads as cancelled.
                try? await Task.sleep(for: .milliseconds(100))
                unwound.mark()
                throw error
            }
        }
        let converterStopped = Flag()
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.converter,
            status: ConverterJobReporting.status(isConverting: true, filename: "Loop.m4a", percent: 0.3),
            cancel: { [weak center] in
                converterStopped.mark()
                center?.setExtraJob(sourceID: ShellJobExtraSourceID.converter, status: nil)
            }
        )
        let vaultQuitCancelled = Flag()
        let vaultSheetRequested = Flag()
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.vaultTransfer,
            status: ShellJobStatus(id: ShellJobExtraSourceID.vaultTransfer, title: "Summer Song"),
            cancel: { vaultSheetRequested.mark() },
            quitCancel: { [weak center] in
                Task { @MainActor in
                    vaultQuitCancelled.mark()
                    center?.setExtraJob(sourceID: ShellJobExtraSourceID.vaultTransfer, status: nil)
                }
            }
        )
        let coordinator = HubTerminationCoordinator(
            jobStatusCenter: center,
            deadline: .seconds(30),
            pollInterval: .milliseconds(10)
        )
        guard case .ask = coordinator.decision() else { return XCTFail("Running work must ask") }

        let replied = expectation(description: "reply")
        coordinator.cancelRunningWork {
            XCTAssertTrue(unwound.isMarked, "reply must wait until the cancelled download has unwound")
            XCTAssertFalse(center.hasUnfinishedQuitBlockingWork)
            replied.fulfill()
        }

        XCTAssertEqual(runner.job(id: job.id)?.state, .canceled)
        XCTAssertTrue(converterStopped.isMarked)
        XCTAssertFalse(vaultSheetRequested.isMarked, "quit must not open the Vault stop sheet")
        await fulfillment(of: [replied], timeout: 10)
        XCTAssertTrue(vaultQuitCancelled.isMarked)
    }

    /// Review finding: a download cancelled from the jobs strip leaves the list at
    /// once, but its partial-file cleanup is still running. Quit waits for it.
    func testCancelledDownloadStillUnwindingWaitsWithoutAsking() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let started = Flag()
        let release = Flag()
        let unwound = Flag()
        let job = runner.enqueue(title: "Track Mix", sourceToolID: "downloader") { _ in
            started.mark()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                while !release.isMarked {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                unwound.mark()
                throw error
            }
        }
        while !started.isMarked {
            try await Task.sleep(for: .milliseconds(5))
        }
        center.cancel(id: job.id.uuidString)
        let coordinator = HubTerminationCoordinator(
            jobStatusCenter: center,
            deadline: .seconds(30),
            pollInterval: .milliseconds(10)
        )

        XCTAssertTrue(center.quitBlockingWork.isEmpty)
        XCTAssertEqual(coordinator.decision(), .waitForCancelledWork)

        let replied = expectation(description: "reply")
        coordinator.cancelRunningWork {
            XCTAssertTrue(unwound.isMarked, "reply must wait for the cancelled download's cleanup")
            replied.fulfill()
        }
        try await Task.sleep(for: .milliseconds(50))
        release.mark()
        await fulfillment(of: [replied], timeout: 10)
        XCTAssertEqual(coordinator.decision(), .terminateNow)
    }

    func testConfirmRepliesAtDeadlineWhenACancelNeverFinishes() async throws {
        let center = ShellJobStatusCenter(jobRunner: JobRunner())
        let cancelled = Flag()
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.vaultTransfer,
            status: ShellJobStatus(id: ShellJobExtraSourceID.vaultTransfer, title: "Hung Transfer"),
            cancel: { cancelled.mark() } // never unregisters (a hung stop, ENG-14)
        )
        let ticks = Counter()
        let coordinator = HubTerminationCoordinator(
            jobStatusCenter: center,
            deadline: .seconds(5),
            pollInterval: .milliseconds(50),
            sleep: { _ in
                ticks.increment()
                await Task.yield()
            }
        )

        let replied = expectation(description: "reply")
        coordinator.cancelRunningWork { replied.fulfill() }
        await fulfillment(of: [replied], timeout: 5)

        XCTAssertTrue(cancelled.isMarked)
        XCTAssertTrue(center.hasUnfinishedQuitBlockingWork, "the hung work is still registered")
        XCTAssertEqual(ticks.value, 100, "the deadline is 5 s in 50 ms polls")
    }

    func testSecondConfirmDoesNotReplyTwice() async throws {
        let center = ShellJobStatusCenter(jobRunner: JobRunner())
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.converter,
            status: ShellJobStatus(id: ShellJobExtraSourceID.converter, title: "Loop.m4a"),
            cancel: { [weak center] in
                center?.setExtraJob(sourceID: ShellJobExtraSourceID.converter, status: nil)
            }
        )
        let coordinator = HubTerminationCoordinator(jobStatusCenter: center, pollInterval: .milliseconds(10))
        let replies = Counter()
        let replied = expectation(description: "reply")
        coordinator.cancelRunningWork {
            replies.increment()
            replied.fulfill()
        }
        XCTAssertTrue(coordinator.isStoppingWork)
        coordinator.cancelRunningWork { replies.increment() }
        await fulfillment(of: [replied], timeout: 5)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(replies.value, 1)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() { lock.withLock { marked = true } }
    var isMarked: Bool { lock.withLock { marked } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
