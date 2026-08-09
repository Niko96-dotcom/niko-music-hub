import Foundation
import XCTest
@testable import NikoMusicCore

final class VaultAutomationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testEligibilityCoversInactivityDiskPressureKeepLocalAndUnknownInputs() {
        let evaluator = VaultAutomationEligibilityEvaluator()
        let policy = VaultAutomationPolicy(
            isVaultEnabled: true,
            isAutomaticArchivingEnabled: true,
            inactivityDays: 30,
            minimumFreeSpaceGiB: 120
        )

        XCTAssertEqual(evaluator.evaluate(candidate(lastActivityDaysAgo: 31), policy: policy, now: now), .eligible(.inactivity))
        XCTAssertEqual(
            evaluator.evaluate(candidate(lastActivityDaysAgo: 2, freeSpaceGiB: 119), policy: policy, now: now),
            .eligible(.diskPressure)
        )
        XCTAssertEqual(
            evaluator.evaluate(candidate(keepLocal: true, lastActivityDaysAgo: 31), policy: policy, now: now),
            .postponed(.keepLocal)
        )
        XCTAssertEqual(
            evaluator.evaluate(candidate(lastActivityDaysAgo: nil), policy: policy, now: now),
            .postponed(.unknownLastActivity)
        )
        XCTAssertEqual(
            evaluator.evaluate(candidate(lastActivityDaysAgo: 2, freeSpaceGiB: nil), policy: policy, now: now),
            .postponed(.notOldEnoughAndNoDiskPressure)
        )
    }

    func testEveryBusyOrUncertainActivityProbePostponesWithoutArchiving() async {
        let cases: [(VaultActivityStatus, VaultActivityStatus, VaultActivityStatus, VaultAutomationPostponement)] = [
            (.busy, .clear, .clear, .cubaseRunning),
            (.uncertain("cubase-probe"), .clear, .clear, .uncertainActivity("cubase-probe")),
            (.clear, .busy, .clear, .openFiles),
            (.clear, .uncertain("open-file-probe"), .clear, .uncertainActivity("open-file-probe")),
            (.clear, .clear, .busy, .recentWriteActivity),
            (.clear, .clear, .uncertain("write-probe"), .uncertainActivity("write-probe"))
        ]

        for (cubase, openFiles, writes, expected) in cases {
            let archiver = RecordingAutomaticArchiver()
            let fixedNow = now
            let scheduler = VaultAutomationScheduler(
                policy: enabledPolicy,
                activityProbe: FixedActivityProbe(cubase: cubase, openFiles: openFiles, writes: writes),
                archiver: archiver,
                now: { fixedNow }
            )

            let results = await scheduler.run(candidates: [candidate(lastActivityDaysAgo: 31)])

            XCTAssertEqual(results, [.postponed(candidateID, expected)])
            let archiveCalls = await archiver.archiveCallCount()
            let removalCalls = await archiver.removalCallCount()
            XCTAssertEqual(archiveCalls, 0)
            XCTAssertEqual(removalCalls, 0)
        }
    }

    func testActivityBecomingBusyAfterCopyRetainsActiveCopy() async {
        let archiver = RecordingAutomaticArchiver()
        let probe = SequencedActivityProbe(cubase: [.clear, .busy], openFiles: [.clear], writes: [.clear])
        let fixedNow = now
        let scheduler = VaultAutomationScheduler(
            policy: enabledPolicy,
            activityProbe: probe,
            archiver: archiver,
            now: { fixedNow }
        )

        let results = await scheduler.run(candidates: [candidate(lastActivityDaysAgo: 31)])

        XCTAssertEqual(results, [.postponed(candidateID, .cubaseRunning)])
        let archiveCalls = await archiver.archiveCallCount()
        let removalCalls = await archiver.removalCallCount()
        XCTAssertEqual(archiveCalls, 1)
        XCTAssertEqual(removalCalls, 0)
    }

    func testUnattendedFixtureAutomationArchivesAndRemovesActiveOnlyAfterPersistedVerification() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(activeRoot: fixture.active, archiveRoot: fixture.archive, store: store)
        let fixedNow = now
        let scheduler = VaultAutomationScheduler(
            policy: enabledPolicy,
            activityProbe: FixedActivityProbe(cubase: .clear, openFiles: .clear, writes: .clear),
            archiver: engine,
            now: { fixedNow }
        )

        let results = await scheduler.run(candidates: [
            VaultAutomationCandidate(
                projectID: candidateID,
                sourceURL: fixture.source,
                isKeepLocal: false,
                lastActivityAt: now.addingTimeInterval(-31 * 86_400),
                availableCapacityBytes: 500 * 1_073_741_824
            )
        ])

        guard case let .archived(projectID, record) = results.first else {
            return XCTFail("Expected unattended archive success, got \(results)")
        }
        XCTAssertEqual(projectID, candidateID)
        XCTAssertEqual(record.state, .archivedLocal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destinationURL.path))
        XCTAssertEqual(try store.record(id: record.id)?.state, .archivedLocal)
    }

    func testActiveDeletionRejectsUnpersistedEvidenceAndRetainsSource() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(activeRoot: fixture.active, archiveRoot: fixture.archive, store: store)
        var forged = VaultTransferRecord(
            projectID: candidateID,
            sourceURL: fixture.source,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/forged"),
            destinationURL: fixture.archive.appendingPathComponent("generations/forged")
        )
        forged.state = .archiveVerified

        do {
            _ = try await engine.removeActiveCopy(after: forged)
            XCTFail("Expected deletion without persisted archive evidence to fail")
        } catch let error as LocalVaultTransferError {
            XCTAssertEqual(error, .missingPersistedArchiveEvidence)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testCubaseProcessDetectionMatchesOnlyTheSteinbergExecutableShape() {
        XCTAssertTrue(CubaseProcessDetector.isCubaseExecutable("/Applications/Cubase 15.app/Contents/MacOS/Cubase 15"))
        XCTAssertTrue(CubaseProcessDetector.isCubaseExecutable("Cubase"))
        XCTAssertFalse(CubaseProcessDetector.isCubaseExecutable("/Applications/Ableton Cubase Keys.app/Contents/MacOS/ableton-cubase-keys"))
        XCTAssertFalse(CubaseProcessDetector.isCubaseExecutable("/Applications/Cubase Song Archive Browser.app/Contents/MacOS/Cubase Song Archive Browser"))
        XCTAssertFalse(CubaseProcessDetector.isCubaseExecutable("Cubase helper"))
    }

    func testCubaseProcessListDetectionIgnoresUnrelatedNames() {
        let unrelated = """
        /Applications/Ableton Cubase Keys.app/Contents/MacOS/ableton-cubase-keys
        /Applications/Cubase Song Archive Browser.app/Contents/MacOS/Cubase Song Archive Browser
        """
        XCTAssertFalse(CubaseProcessDetector.containsCubase(inProcessList: unrelated))
        XCTAssertTrue(CubaseProcessDetector.containsCubase(
            inProcessList: unrelated + "\n/Applications/Cubase 15.app/Contents/MacOS/Cubase 15\n"
        ))
    }

    func testTimedOutLsofProbePostponesInsteadOfClaimingProjectIsClear() async {
        let runner = FixedVaultActivityCommandRunner(status: .timedOut)
        let probe = SystemVaultAutomationActivityProbe(
            commandRunner: runner,
            activeUseProbeTimeout: 0.01
        )
        let projectURL = URL(fileURLWithPath: "/tmp/project with spaces", isDirectory: true)

        let result = await probe.openFileStatus(in: projectURL)

        XCTAssertEqual(result, .uncertain("probe-timed-out"))
        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.executable, "/usr/sbin/lsof")
        XCTAssertEqual(calls.first?.arguments, ["-nP", "+D", projectURL.path])
    }

    func testBoundedActivityCommandRunnerReturnsAtDeadline() async throws {
        let executable = "/bin/sleep"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: executable))
        let startedAt = ContinuousClock.now

        let result = await FoundationVaultActivityCommandRunner().status(
            executable: executable,
            arguments: ["10"],
            timeout: 0.05
        )

        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(startedAt.duration(to: .now), .seconds(1))
    }

    func testBoundedActivityCommandRunnerCancelsPromptly() async throws {
        let executable = "/bin/sleep"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: executable))
        let runner = FoundationVaultActivityCommandRunner()
        let task = Task {
            await runner.status(executable: executable, arguments: ["10"], timeout: 10)
        }
        try await Task.sleep(for: .milliseconds(25))
        let cancelledAt = ContinuousClock.now
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertLessThan(cancelledAt.duration(to: .now), .seconds(1))
    }

    func testWriteActivityProbeTimesOutFailClosedBeforeRecursiveScan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: root.appendingPathComponent("fixture.cpr"))
        let probe = SystemVaultAutomationActivityProbe(
            commandRunner: FixedVaultActivityCommandRunner(status: .exited(1)),
            activeUseProbeTimeout: 0
        )

        let result = await probe.writeActivityStatus(in: root, since: .distantPast)

        XCTAssertEqual(result, .uncertain("probe-timed-out"))
    }

    private var candidateID: ProjectID {
        ProjectID(rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
    }

    private var enabledPolicy: VaultAutomationPolicy {
        VaultAutomationPolicy(isVaultEnabled: true, isAutomaticArchivingEnabled: true)
    }

    private func candidate(
        keepLocal: Bool = false,
        lastActivityDaysAgo: Int?,
        freeSpaceGiB: Int? = 500
    ) -> VaultAutomationCandidate {
        VaultAutomationCandidate(
            projectID: candidateID,
            sourceURL: URL(fileURLWithPath: "/tmp/fixture-project"),
            isKeepLocal: keepLocal,
            lastActivityAt: lastActivityDaysAgo.map { now.addingTimeInterval(-Double($0) * 86_400) },
            availableCapacityBytes: freeSpaceGiB.map { Int64($0) * 1_073_741_824 }
        )
    }
}

private struct FixedActivityProbe: VaultAutomationActivityProbing {
    let cubase: VaultActivityStatus
    let openFiles: VaultActivityStatus
    let writes: VaultActivityStatus

    func cubaseStatus() async -> VaultActivityStatus { cubase }
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { openFiles }
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { writes }
}

private actor SequencedActivityProbe: VaultAutomationActivityProbing {
    private var cubase: [VaultActivityStatus]
    private var openFiles: [VaultActivityStatus]
    private var writes: [VaultActivityStatus]

    init(cubase: [VaultActivityStatus], openFiles: [VaultActivityStatus], writes: [VaultActivityStatus]) {
        self.cubase = cubase
        self.openFiles = openFiles
        self.writes = writes
    }

    func cubaseStatus() async -> VaultActivityStatus { cubase.removeFirst() }
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { openFiles.removeFirst() }
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { writes.removeFirst() }
}

private struct VaultActivityCommandCall: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let timeout: TimeInterval
}

private actor FixedVaultActivityCommandRunner: VaultActivityCommandRunning {
    let nextStatus: VaultActivityCommandStatus
    private(set) var calls: [VaultActivityCommandCall] = []

    init(status: VaultActivityCommandStatus) {
        self.nextStatus = status
    }

    func status(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> VaultActivityCommandStatus {
        calls.append(VaultActivityCommandCall(executable: executable, arguments: arguments, timeout: timeout))
        return nextStatus
    }
}

private actor RecordingAutomaticArchiver: VaultAutomaticArchiving {
    private var archiveCalls = 0
    private var removalCalls = 0

    func archive(projectID: ProjectID, sourceURL: URL) async throws -> VaultTransferRecord {
        archiveCalls += 1
        var record = VaultTransferRecord(
            projectID: projectID,
            sourceURL: sourceURL,
            stagingURL: URL(fileURLWithPath: "/tmp/staging"),
            destinationURL: URL(fileURLWithPath: "/tmp/archive")
        )
        record.state = .archiveVerified
        return record
    }

    func removeActiveCopy(after archivedRecord: VaultTransferRecord) async throws -> VaultTransferRecord {
        removalCalls += 1
        var record = archivedRecord
        record.state = .archivedLocal
        return record
    }

    func archiveCallCount() -> Int { archiveCalls }
    func removalCallCount() -> Int { removalCalls }
}

private struct AutomationFixture {
    let root: URL
    let active: URL
    let archive: URL
    let source: URL
    let databaseURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-automation-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        source = active.appendingPathComponent("Fixture Song", isDirectory: true)
        databaseURL = root.appendingPathComponent("state/vault.sqlite")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("fixture-cubase-project".utf8).write(to: source.appendingPathComponent("Fixture Song.cpr"))
        try Data(repeating: 42, count: 4096).write(to: source.appendingPathComponent("Audio/take.wav"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
