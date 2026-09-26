import AppCore
@testable import FeatureArchiveBrowser
import Combine
import Foundation
import XCTest

/// Focused owner tests for `ProjectVaultOperationCoordinator`: serial
/// dispatch, cancel/requeue per-request accounting, bounded retry
/// cancellation/reset, and observation/lifetime. Deterministic entry gates
/// (no blanket sleeps); bounded polling only for MainActor state transitions.
@MainActor
final class ProjectVaultOperationCoordinatorTests: XCTestCase {
    actor Gate {
        var entered = 0
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        func enterAndWait() async {
            entered += 1
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    final class StatusBox {
        var last: String?
        var all: [String] = []
    }

    private func makeTrackedCoordinator(rootIDs: [UUID?]) -> (ProjectVaultOperationCoordinator, StatusBox) {
        let box = StatusBox()
        let coordinator = ProjectVaultOperationCoordinator()
        coordinator.currentRootIDs = { rootIDs }
        coordinator.currentStatusBase = { box.last }
        coordinator.onStatus = {
            box.last = $0
            if let message = $0 { box.all.append(message) }
        }
        coordinator.refreshPresentationForDispatch = {}
        coordinator.onActiveChanged = {}
        coordinator.onLogStart = { _ in }
        coordinator.onLogFinish = { _, _, _ in }
        coordinator.onQueueDrained = {}
        return (coordinator, box)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for operation coordinator state", file: file, line: line)
    }

    /// Deterministic gate-entry wait: polls the actor's `entered` count via an
    /// async-safe condition and releases the gate if the wait times out so a
    /// failed test cannot hang a gated `perform` forever.
    private func waitForEntry(
        _ gate: Gate,
        count: Int = 1,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            try await waitUntil(timeout: timeout, file: file, line: line) {
                await gate.entered >= count
            }
        } catch {
            await gate.open()
            throw error
        }
    }

    // MARK: - Serial queue with deterministic entry

    func testSerialDispatchRunsOneAtATimeInOrder() async throws {
        let (coordinator, _) = makeTrackedCoordinator(rootIDs: [nil, nil])
        let gateA = Gate()
        let gateB = Gate()
        defer {
            Task { await gateA.open(); await gateB.open() }
        }
        var order: [String] = []

        coordinator.enqueue(
            songID: "a", projectKey: "key-a", songName: "A",
            label: "Archive", startMessage: "Starting A",
            rootIDs: [nil, nil], trigger: .manual
        ) {
            await gateA.enterAndWait()
            order.append("a")
            return true
        }
        coordinator.enqueue(
            songID: "b", projectKey: "key-b", songName: "B",
            label: "Archive", startMessage: "Starting B",
            rootIDs: [nil, nil], trigger: .manual
        ) {
            await gateB.enterAndWait()
            order.append("b")
            return true
        }

        try await waitForEntry(gateA)
        XCTAssertEqual(coordinator.activeOperation?.songID, "a")
        XCTAssertEqual(coordinator.pendingOperations.map(\.songID), ["b"])
        XCTAssertEqual(coordinator.busySongIDs, ["a", "b"])
        // Duplicate by song AND project identity is prevented.
        XCTAssertFalse(coordinator.enqueue(
            songID: "b", projectKey: "key-b", songName: "B",
            label: "Archive", startMessage: "dup",
            rootIDs: [nil, nil], trigger: .manual
        ) { true })
        XCTAssertFalse(coordinator.enqueue(
            songID: "other", projectKey: "key-a", songName: "Other",
            label: "Archive", startMessage: "dup",
            rootIDs: [nil, nil], trigger: .manual
        ) { true })

        await gateA.open()
        try await waitForEntry(gateB)
        XCTAssertEqual(coordinator.activeOperation?.songID, "b")
        XCTAssertTrue(coordinator.pendingOperations.isEmpty)
        await gateB.open()
        try await waitUntil { coordinator.isIdle && coordinator.activeOperation == nil }
        XCTAssertEqual(order, ["a", "b"])
        XCTAssertEqual(coordinator.queueBatchCount, 2)
        XCTAssertTrue(coordinator.queueFailures.isEmpty)
        XCTAssertNil(coordinator.queueTask)
    }

    // MARK: - Cancel / requeue per-request accounting

    func testCancelRequeueKeepsPerRequestCounts() async throws {
        let (coordinator, box) = makeTrackedCoordinator(rootIDs: [nil, nil])
        let gateA = Gate()
        defer { Task { await gateA.open() } }
        coordinator.enqueue(
            songID: "a", projectKey: "key-a", songName: "A",
            label: "Archive", startMessage: "Starting A",
            rootIDs: [nil, nil], trigger: nil
        ) {
            await gateA.enterAndWait()
            return false
        }
        coordinator.enqueue(
            songID: "b", projectKey: "key-b", songName: "B",
            label: "Archive", startMessage: "Starting B",
            rootIDs: [nil, nil], trigger: nil
        ) { true }
        try await waitUntil { coordinator.pendingOperations.contains(where: { $0.songID == "b" }) }

        coordinator.cancelQueued(songID: "b", songTitle: "B")
        XCTAssertFalse(coordinator.pendingOperations.contains(where: { $0.songID == "b" }))
        XCTAssertEqual(coordinator.canceledRequestCountForBatch, 1)
        XCTAssertEqual(coordinator.canceledIDsForBatch, ["b"])
        XCTAssertFalse(coordinator.busySongIDs.contains("b"))

        coordinator.enqueue(
            songID: "b", projectKey: "key-b", songName: "B",
            label: "Archive", startMessage: "Starting B",
            rootIDs: [nil, nil], trigger: nil
        ) { true }
        XCTAssertEqual(coordinator.queueBatchCount, 3)
        coordinator.cancelQueued(songID: "b", songTitle: "B")
        XCTAssertEqual(coordinator.canceledRequestCountForBatch, 2)
        XCTAssertEqual(coordinator.canceledIDsForBatch, ["b"])

        coordinator.confirmStopActiveTransfer()
        await gateA.open()
        try await waitUntil { coordinator.isIdle }
        XCTAssertEqual(coordinator.stoppedRequestCountForBatch, 1)
        XCTAssertEqual(coordinator.stoppedIDsForBatch, ["a"])
        let footer = try XCTUnwrap(box.last)
        XCTAssertTrue(footer.contains("0 completed"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("1 stopped"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("2 cancelled"), "footer was: \(footer)")
        XCTAssertTrue(footer.contains("of 3"), "footer was: \(footer)")
    }

    func testCancelAllPendingCountsEveryRequest() async throws {
        let (coordinator, _) = makeTrackedCoordinator(rootIDs: [nil, nil])
        let gate = Gate()
        defer { Task { await gate.open() } }
        coordinator.enqueue(
            songID: "a", projectKey: "key-a", songName: "A",
            label: "Archive", startMessage: "A",
            rootIDs: [nil, nil], trigger: nil
        ) {
            await gate.enterAndWait()
            return true
        }
        coordinator.enqueue(
            songID: "b", projectKey: "key-b", songName: "B",
            label: "Archive", startMessage: "B",
            rootIDs: [nil, nil], trigger: nil
        ) { true }
        coordinator.enqueue(
            songID: "c", projectKey: "key-c", songName: "C",
            label: "Archive", startMessage: "C",
            rootIDs: [nil, nil], trigger: nil
        ) { true }
        try await waitUntil { coordinator.pendingOperations.count == 2 }
        // Active holds the first; cancel-all records one request per pending item.
        coordinator.cancelAllPending()
        XCTAssertTrue(coordinator.pendingOperations.isEmpty)
        XCTAssertEqual(coordinator.canceledRequestCountForBatch, 2)
        XCTAssertEqual(coordinator.canceledIDsForBatch, ["b", "c"])
        XCTAssertTrue(coordinator.busySongIDs.contains("a"))
        await gate.open()
        try await waitUntil { coordinator.isIdle }
    }

    // MARK: - Done revoke preserves manual work

    /// Duplicate prevention (by song) means one song can never hold two
    /// pending requests, so Done/manual separation is exercised with distinct
    /// songs plus an active-manual same-song guard. Revoking the manual song
    /// leaves it untouched; revoking Done removes only Done.
    func testRevokeDonePreservesManualRequests() async throws {
        let (coordinator, _) = makeTrackedCoordinator(rootIDs: [nil, nil])
        let gate = Gate()
        defer { Task { await gate.open() } }
        coordinator.enqueue(
            songID: "a", projectKey: "key-a", songName: "A",
            label: "Archive", startMessage: "A",
            rootIDs: [nil, nil], trigger: .manual
        ) {
            await gate.enterAndWait()
            return false
        }
        coordinator.enqueue(
            songID: "b", projectKey: "key-b", songName: "B",
            label: "Archive", startMessage: "B",
            rootIDs: [nil, nil], trigger: .workflowDone
        ) { true }
        coordinator.enqueue(
            songID: "c", projectKey: "key-c", songName: "C",
            label: "Archive", startMessage: "C manual",
            rootIDs: [nil, nil], trigger: .manual
        ) { true }
        try await waitUntil { coordinator.pendingOperations.count == 2 }

        // Revoking the manual song is a no-op: Done-only revocation never
        // touches manual triggers.
        coordinator.revokeDoneWork(songID: "c")
        XCTAssertEqual(Set(coordinator.pendingOperations.map(\.songID)), ["b", "c"])
        XCTAssertTrue(coordinator.busySongIDs.contains("c"))
        XCTAssertEqual(
            coordinator.pendingOperations.first(where: { $0.songID == "c" })?.trigger,
            .manual
        )

        // Active manual same-song guard: revoking the active manual song
        // never stops its transfer.
        coordinator.revokeDoneWork(songID: "a")
        XCTAssertEqual(coordinator.activeOperation?.songID, "a")
        XCTAssertTrue(coordinator.busySongIDs.contains("a"))

        // Revoking Done removes only the Done request; the manual survivor
        // keeps the song busy with no spurious cancel message.
        coordinator.revokeDoneWork(songID: "b")
        XCTAssertEqual(coordinator.pendingOperations.map(\.songID), ["c"])
        XCTAssertFalse(coordinator.busySongIDs.contains("b"))
        XCTAssertTrue(coordinator.busySongIDs.contains("c"))
        XCTAssertNil(coordinator.retryTasks["b"])

        coordinator.cancelQueued(songID: "c", songTitle: "C")
        XCTAssertFalse(coordinator.busySongIDs.contains("c"))
        coordinator.confirmStopActiveTransfer()
        await gate.open()
        try await waitUntil { coordinator.isIdle }
    }

    // MARK: - Bounded retry + capacity

    func testBoundedRetryBudgetAndCancelReset() async throws {
        let (coordinator, _) = makeTrackedCoordinator(rootIDs: [nil, nil])
        coordinator.doneRetryDelay = .milliseconds(20)
        var legitimateFires = 0
        var canceledFires = 0
        XCTAssertTrue(coordinator.scheduleRetry(for: "s") { canceledFires += 1 })
        XCTAssertNotNil(coordinator.retryTasks["s"])
        XCTAssertEqual(coordinator.retryAttemptCounts["s"], 1)
        // A second schedule while one waits is refused (same budget).
        XCTAssertFalse(coordinator.scheduleRetry(for: "s") { legitimateFires += 1 })
        coordinator.cancelPendingRetry(for: "s")
        XCTAssertNil(coordinator.retryTasks["s"])
        XCTAssertNil(coordinator.retryAttemptCounts["s"])
        // Let the cancelled timer pass its deadline: a missed cancel would
        // fire here and increment the canceled counter.
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(canceledFires, 0, "cancelled retry must never fire")

        // Exhaust the budget: three schedules succeed, the fourth is refused.
        for _ in 0..<3 {
            XCTAssertTrue(coordinator.scheduleRetry(for: "s") { legitimateFires += 1 })
            try await waitUntil { coordinator.retryTasks["s"] == nil }
        }
        XCTAssertEqual(coordinator.retryAttemptCounts["s"], 3)
        XCTAssertFalse(coordinator.scheduleRetry(for: "s") { legitimateFires += 1 })
        // Explicit confirmation restarts the budget.
        coordinator.cancelPendingRetry(for: "s")
        XCTAssertTrue(coordinator.scheduleRetry(for: "s") { legitimateFires += 1 })
        try await waitUntil { coordinator.retryTasks["s"] == nil }
        XCTAssertEqual(legitimateFires, 4, "exactly 4 legitimate retries must fire")
        XCTAssertEqual(canceledFires, 0, "cancelled retry must never fire")
    }

    func testCapacityPostponementRelease() {
        let (coordinator, _) = makeTrackedCoordinator(rootIDs: [nil, nil])
        XCTAssertFalse(coordinator.isCapacityPostponed(songID: "s"))
        coordinator.noteCapacityPostponed(songID: "s")
        XCTAssertTrue(coordinator.isCapacityPostponed(songID: "s"))
        coordinator.noteSuccessfulTransfer(for: "s")
        XCTAssertFalse(coordinator.isCapacityPostponed(songID: "s"))
        XCTAssertNil(coordinator.retryTasks["s"])

        coordinator.noteCapacityPostponed(songID: "s")
        coordinator.cancelDoneRetry(for: "s")
        XCTAssertFalse(coordinator.isCapacityPostponed(songID: "s"))
    }

    // MARK: - Lifetime

    func testTeardownCancelsDelayedRetry() async throws {
        let (coordinator, _) = makeTrackedCoordinator(rootIDs: [nil, nil])
        coordinator.doneRetryDelay = .milliseconds(50)
        var fired = false
        XCTAssertTrue(coordinator.scheduleRetry(for: "s") { fired = true })
        XCTAssertNotNil(coordinator.retryTasks["s"])
        coordinator.cancelForTeardown()
        XCTAssertNil(coordinator.retryTasks["s"])
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(fired)
    }

    // MARK: - Coordinator-to-VM notification forwarding

    /// Verifies the owner emits its narrow callbacks (status, active-change,
    /// logging, drain) across one serial operation without asserting exact
    /// publish counts. Views observe only pending/active/busy/messages; batch
    /// bookkeeping stays non-published.
    func testCoordinatorForwardsStatusActiveLogAndDrain() async throws {
        let (coordinator, box) = makeTrackedCoordinator(rootIDs: [nil, nil])
        let gate = Gate()
        defer { Task { await gate.open() } }
        var didEnterActive = false
        var didExitActive = false
        var didLogStart = false
        var didLogFinish = false
        var didDrain = false
        coordinator.onActiveChanged = { [weak coordinator] in
            guard let coordinator else { return }
            if coordinator.activeOperation != nil {
                didEnterActive = true
            } else {
                didExitActive = true
            }
        }
        coordinator.onLogStart = { _ in didLogStart = true }
        coordinator.onLogFinish = { _, _, _ in didLogFinish = true }
        coordinator.onQueueDrained = { didDrain = true }

        coordinator.enqueue(
            songID: "a", projectKey: "key-a", songName: "A",
            label: "Archive", startMessage: "Starting A",
            rootIDs: [nil, nil], trigger: .manual
        ) {
            await gate.enterAndWait()
            return true
        }
        try await waitForEntry(gate)
        XCTAssertTrue(didEnterActive, "active-change must fire on entry")
        XCTAssertTrue(didLogStart, "log-start must fire on entry")
        XCTAssertEqual(box.last, "Starting A")
        await gate.open()
        try await waitUntil { coordinator.isIdle && coordinator.activeOperation == nil }
        XCTAssertTrue(didExitActive, "active-change must fire on exit")
        XCTAssertTrue(didLogFinish, "log-finish must fire on exit")
        XCTAssertTrue(didDrain, "drain must fire after the last operation")
    }

    /// View-model forwarding: removing a per-song message through the owner
    /// emits `VM.objectWillChange` with no status callback involved. Fails if
    /// `wireVaultOperationCoordinator`'s sink forwarding is removed; does not
    /// pass merely via VM status/other Published mutations because the removal
    /// path publishes only `operationMessages`.
    func testViewModelForwardsOperationMessageRemoval() async throws {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        defer { viewModel.vaultOperations.cancelForTeardown() }
        let gate = Gate()
        defer { Task { await gate.open() } }
        let rootIDs = viewModel.vaultQueueRootIDs
        viewModel.vaultOperations.enqueue(
            songID: "fwd-a", projectKey: "fwd-key-a", songName: "Fwd A",
            label: "Archive", startMessage: "Starting Fwd A",
            rootIDs: rootIDs, trigger: .manual
        ) {
            await gate.enterAndWait()
            return true
        }
        viewModel.vaultOperations.enqueue(
            songID: "fwd-b", projectKey: "fwd-key-b", songName: "Fwd B",
            label: "Archive", startMessage: "Starting Fwd B",
            rootIDs: rootIDs, trigger: .manual
        ) { true }
        try await waitUntil { viewModel.projectVaultPendingOperations.contains(where: { $0.songID == "fwd-b" }) }

        // Build a real per-song message by canceling the queued request while
        // a different operation is gated.
        viewModel.vaultOperations.cancelQueued(songID: "fwd-b", songTitle: "Fwd B")
        XCTAssertEqual(
            viewModel.projectVaultOperationMessages["fwd-b"],
            "Queued request cancelled. No project files were changed."
        )

        final class ForwardFlag: @unchecked Sendable { var didNotify = false }
        let flag = ForwardFlag()
        let subscription = viewModel.objectWillChange.sink { _ in flag.didNotify = true }
        defer { subscription.cancel() }
        flag.didNotify = false

        // This mutation alone has no status callback, so a VM notification
        // proves true `objectWillChange` forwarding.
        viewModel.vaultOperations.removeOperationMessage(forKey: "fwd-b")
        XCTAssertNil(viewModel.projectVaultOperationMessages["fwd-b"])
        XCTAssertTrue(flag.didNotify, "VM must forward coordinator operationMessages removal")

        await gate.open()
        try await waitUntil { viewModel.projectVaultActiveOperation == nil && viewModel.projectVaultBusySongIDs.isEmpty }
    }

    /// View-model mirror: the shell job row appears while the coordinator owns
    /// an active operation and clears when it drains. Asserts entry/exit
    /// presence only, never exact publish counts.
    func testViewModelMirrorsCoordinatorActiveJobEntryExit() async throws {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        defer { viewModel.vaultOperations.cancelForTeardown() }
        let gate = Gate()
        defer { Task { await gate.open() } }
        let rootIDs = viewModel.vaultQueueRootIDs
        viewModel.vaultOperations.enqueue(
            songID: "vm-job", projectKey: "vm-job-key", songName: "VM Job",
            label: "Archive", startMessage: "Starting VM Job",
            rootIDs: rootIDs, trigger: .manual
        ) {
            await gate.enterAndWait()
            return true
        }
        try await waitUntil { viewModel.projectVaultActiveOperation != nil }
        XCTAssertTrue(
            viewModel.jobStatusCenter.jobs.contains(where: { $0.id == ShellJobExtraSourceID.vaultTransfer }),
            "vault-transfer job must be present while active"
        )
        await gate.open()
        try await waitUntil { viewModel.projectVaultActiveOperation == nil && viewModel.projectVaultBusySongIDs.isEmpty }
        try await waitUntil {
            !viewModel.jobStatusCenter.jobs.contains(where: { $0.id == ShellJobExtraSourceID.vaultTransfer })
        }
    }

    // MARK: - Weak lifetime (owner release cancels pending retry)

    /// Releasing the coordinator cancels its sleeping retry directly via its
    /// Sendable task handles in `deinit`; the callback never fires after dealloc.
    func testWeakLifetimeCancelsPendingRetry() async throws {
        weak var weakCoordinator: ProjectVaultOperationCoordinator?
        var fired = false
        do {
            let coordinator = ProjectVaultOperationCoordinator()
            weakCoordinator = coordinator
            coordinator.doneRetryDelay = .milliseconds(50)
            XCTAssertTrue(coordinator.scheduleRetry(for: "s") { fired = true })
        }
        XCTAssertNil(weakCoordinator, "coordinator must deallocate with its owner scope")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(fired, "pending retry must not fire after owner released")
    }

    /// The view model solely owns its coordinator, so releasing the view
    /// model releases the owner and cancels any pending retry. Uses a long
    /// retry delay so init recovery settles before the timer could fire.
    func testViewModelReleaseCancelsPendingRetry() async throws {
        weak var weakViewModel: ArchiveBrowserViewModel?
        weak var weakOperations: ProjectVaultOperationCoordinator?
        var fired = false
        do {
            let viewModel = ArchiveBrowserViewModel(
                context: TestToolContext.make(),
                archiveRootWatcher: NoopArchiveRootWatcher()
            )
            weakViewModel = viewModel
            weakOperations = viewModel.vaultOperations
            viewModel.vaultOperations.doneRetryDelay = .milliseconds(200)
            XCTAssertTrue(viewModel.vaultOperations.scheduleRetry(for: "vm-lifetime") { fired = true })
        }
        try await waitUntil(timeout: .seconds(5)) { weakViewModel == nil && weakOperations == nil }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(fired, "pending retry must not fire after view model released")
    }
}
