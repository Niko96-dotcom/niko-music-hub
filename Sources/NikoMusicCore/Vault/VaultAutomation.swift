import Foundation

public struct VaultAutomationPolicy: Equatable, Sendable {
    public var isVaultEnabled: Bool
    public var isAutomaticArchivingEnabled: Bool
    public var inactivityDays: Int
    public var minimumFreeSpaceGiB: Int
    public var writeQuietPeriod: TimeInterval

    public init(
        isVaultEnabled: Bool,
        isAutomaticArchivingEnabled: Bool,
        inactivityDays: Int = 30,
        minimumFreeSpaceGiB: Int = 120,
        writeQuietPeriod: TimeInterval = 10 * 60
    ) {
        self.isVaultEnabled = isVaultEnabled
        self.isAutomaticArchivingEnabled = isAutomaticArchivingEnabled
        self.inactivityDays = inactivityDays
        self.minimumFreeSpaceGiB = minimumFreeSpaceGiB
        self.writeQuietPeriod = writeQuietPeriod
    }
}

public struct VaultAutomationCandidate: Equatable, Sendable {
    public enum Trigger: Equatable, Sendable {
        case policy
        case workflowDone
    }

    public let projectID: ProjectID
    public let sourceURL: URL
    public let isKeepLocal: Bool
    public let lastActivityAt: Date?
    public let availableCapacityBytes: Int64?
    public let trigger: Trigger

    public init(
        projectID: ProjectID,
        sourceURL: URL,
        isKeepLocal: Bool,
        lastActivityAt: Date?,
        availableCapacityBytes: Int64?,
        trigger: Trigger = .policy
    ) {
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.isKeepLocal = isKeepLocal
        self.lastActivityAt = lastActivityAt
        self.availableCapacityBytes = availableCapacityBytes
        self.trigger = trigger
    }
}

public enum VaultAutomationEligibilityReason: Equatable, Sendable {
    case inactivity
    case diskPressure
}

public enum VaultAutomationPostponement: Equatable, Sendable {
    case vaultDisabled
    case automaticArchivingDisabled
    case keepLocal
    case invalidPolicy
    case unknownLastActivity
    case notOldEnoughAndNoDiskPressure
    case cubaseRunning
    case openFiles
    case recentWriteActivity
    case uncertainActivity(String)
}

public enum VaultAutomationEligibility: Equatable, Sendable {
    case eligible(VaultAutomationEligibilityReason)
    case postponed(VaultAutomationPostponement)
}

public struct VaultAutomationEligibilityEvaluator: Sendable {
    public init() {}

    public func evaluate(
        _ candidate: VaultAutomationCandidate,
        policy: VaultAutomationPolicy,
        now: Date
    ) -> VaultAutomationEligibility {
        guard policy.isVaultEnabled else { return .postponed(.vaultDisabled) }
        guard policy.isAutomaticArchivingEnabled else { return .postponed(.automaticArchivingDisabled) }
        guard !candidate.isKeepLocal else { return .postponed(.keepLocal) }
        guard policy.inactivityDays > 0, policy.minimumFreeSpaceGiB >= 0, policy.writeQuietPeriod >= 0 else {
            return .postponed(.invalidPolicy)
        }
        if candidate.trigger == .workflowDone { return .eligible(.inactivity) }
        guard let lastActivity = candidate.lastActivityAt, lastActivity <= now else {
            return .postponed(.unknownLastActivity)
        }
        let seconds = TimeInterval(policy.inactivityDays) * 86_400
        if now.timeIntervalSince(lastActivity) >= seconds { return .eligible(.inactivity) }

        guard let freeBytes = candidate.availableCapacityBytes else {
            return .postponed(.notOldEnoughAndNoDiskPressure)
        }
        let threshold = Int64(policy.minimumFreeSpaceGiB) * 1_073_741_824
        return freeBytes < threshold
            ? .eligible(.diskPressure)
            : .postponed(.notOldEnoughAndNoDiskPressure)
    }
}

public enum VaultActivityStatus: Equatable, Sendable {
    case clear
    case busy
    case uncertain(String)
}

public protocol VaultAutomationActivityProbing: Sendable {
    func cubaseStatus() async -> VaultActivityStatus
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus
}

/// Production probe. Exit statuses other than the documented clear/busy values
/// are uncertainty and therefore postpone work.
public struct SystemVaultAutomationActivityProbe: VaultAutomationActivityProbing, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func cubaseStatus() async -> VaultActivityStatus {
        commandStatus(executable: "/usr/bin/pgrep", arguments: ["-if", "Cubase"])
    }

    public func openFileStatus(in projectURL: URL) async -> VaultActivityStatus {
        commandStatus(executable: "/usr/sbin/lsof", arguments: ["+D", projectURL.path])
    }

    public func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus {
        guard fileManager.fileExists(atPath: projectURL.path) else { return .uncertain("project-missing") }
        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsPackageDescendants]
        ) else { return .uncertain("project-unreadable") }
        while let url = enumerator.nextObject() as? URL {
            do {
                if let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified >= since {
                    return .busy
                }
            } catch { return .uncertain("metadata-unreadable") }
        }
        return .clear
    }

    private func commandStatus(executable: String, arguments: [String]) -> VaultActivityStatus {
        guard fileManager.isExecutableFile(atPath: executable) else { return .uncertain("probe-unavailable") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            switch process.terminationStatus {
            case 0: return .busy
            case 1: return .clear
            default: return .uncertain("probe-failed-\(process.terminationStatus)")
            }
        } catch { return .uncertain("probe-failed") }
    }
}

public protocol VaultAutomaticArchiving: Sendable {
    func archive(projectID: ProjectID, sourceURL: URL) async throws -> VaultTransferRecord
    func removeActiveCopy(after archivedRecord: VaultTransferRecord) async throws -> VaultTransferRecord
}

extension LocalVaultTransferEngine: VaultAutomaticArchiving {}

public struct VaultAutomationFailureNotification: Equatable, Sendable {
    public let projectID: ProjectID
    public let stage: String
    public let message: String

    public init(projectID: ProjectID, stage: String, message: String) {
        self.projectID = projectID
        self.stage = stage
        self.message = message
    }
}

public enum VaultAutomationRunResult: Equatable, Sendable {
    case postponed(ProjectID, VaultAutomationPostponement)
    case archived(ProjectID, VaultTransferRecord)
    case failed(VaultAutomationFailureNotification)
}

/// One quiet, opt-in scheduler pass. Successful and postponed projects emit no
/// notifications; only structured failures are sent to the supplied sink.
public actor VaultAutomationScheduler {
    public typealias FailureSink = @Sendable (VaultAutomationFailureNotification) async -> Void

    private let policy: VaultAutomationPolicy
    private let evaluator: VaultAutomationEligibilityEvaluator
    private let activityProbe: any VaultAutomationActivityProbing
    private let archiver: any VaultAutomaticArchiving
    private let now: @Sendable () -> Date
    private let failureSink: FailureSink
    private let removesActiveCopy: Bool

    public init(
        policy: VaultAutomationPolicy,
        activityProbe: any VaultAutomationActivityProbing,
        archiver: any VaultAutomaticArchiving,
        removesActiveCopy: Bool = true,
        now: @escaping @Sendable () -> Date = Date.init,
        failureSink: @escaping FailureSink = { _ in }
    ) {
        self.policy = policy
        self.evaluator = VaultAutomationEligibilityEvaluator()
        self.activityProbe = activityProbe
        self.archiver = archiver
        self.removesActiveCopy = removesActiveCopy
        self.now = now
        self.failureSink = failureSink
    }

    public func run(candidates: [VaultAutomationCandidate]) async -> [VaultAutomationRunResult] {
        guard policy.isVaultEnabled, policy.isAutomaticArchivingEnabled else {
            let reason: VaultAutomationPostponement = policy.isVaultEnabled ? .automaticArchivingDisabled : .vaultDisabled
            return candidates.map { .postponed($0.projectID, reason) }
        }
        var results: [VaultAutomationRunResult] = []
        for candidate in candidates {
            let eligibility = evaluator.evaluate(candidate, policy: policy, now: now())
            guard case .eligible = eligibility else {
                if case let .postponed(reason) = eligibility { results.append(.postponed(candidate.projectID, reason)) }
                continue
            }
            if let postponed = await activityPostponement(for: candidate) {
                results.append(.postponed(candidate.projectID, postponed))
                continue
            }
            do {
                let archived = try await archiver.archive(projectID: candidate.projectID, sourceURL: candidate.sourceURL)
                if !removesActiveCopy {
                    results.append(.archived(candidate.projectID, archived))
                    continue
                }
                // Repeat every volatile safety check after the copy. If anything
                // became busy or uncertain, retain both copies.
                if let postponed = await activityPostponement(for: candidate) {
                    results.append(.postponed(candidate.projectID, postponed))
                    continue
                }
                let completed = try await archiver.removeActiveCopy(after: archived)
                results.append(.archived(candidate.projectID, completed))
            } catch {
                let failure = VaultAutomationFailureNotification(
                    projectID: candidate.projectID,
                    stage: "automatic-archive",
                    message: String(describing: error)
                )
                await failureSink(failure)
                results.append(.failed(failure))
            }
        }
        return results
    }

    private func activityPostponement(for candidate: VaultAutomationCandidate) async -> VaultAutomationPostponement? {
        switch await activityProbe.cubaseStatus() {
        case .clear: break
        case .busy: return .cubaseRunning
        case let .uncertain(reason): return .uncertainActivity(reason)
        }
        switch await activityProbe.openFileStatus(in: candidate.sourceURL) {
        case .clear: break
        case .busy: return .openFiles
        case let .uncertain(reason): return .uncertainActivity(reason)
        }
        switch await activityProbe.writeActivityStatus(in: candidate.sourceURL, since: now().addingTimeInterval(-policy.writeQuietPeriod)) {
        case .clear: return nil
        case .busy: return .recentWriteActivity
        case let .uncertain(reason): return .uncertainActivity(reason)
        }
    }
}
