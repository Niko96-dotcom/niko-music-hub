import Foundation

public struct VaultAutomationPolicy: Equatable, Sendable {
    public var isVaultEnabled: Bool
    public var transferFreeSpaceReserveGiB: Int
    public var writeQuietPeriod: TimeInterval

    public init(
        isVaultEnabled: Bool,
        transferFreeSpaceReserveGiB: Int = 5,
        writeQuietPeriod: TimeInterval = 10 * 60
    ) {
        self.isVaultEnabled = isVaultEnabled
        self.transferFreeSpaceReserveGiB = transferFreeSpaceReserveGiB
        self.writeQuietPeriod = writeQuietPeriod
    }
}

/// One Done project to archive. Keep Local was checked before the run.
public struct VaultAutomationCandidate: Equatable, Sendable {
    public let projectID: ProjectID
    public let sourceURL: URL
    /// Free bytes on the Archive destination volume before a new automatic write.
    public let archiveAvailableCapacityBytes: Int64?
    /// Logical bytes the automatic Archive write is projected to add.
    public let projectedArchiveBytes: Int64?

    public init(
        projectID: ProjectID,
        sourceURL: URL,
        archiveAvailableCapacityBytes: Int64?,
        projectedArchiveBytes: Int64?
    ) {
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.archiveAvailableCapacityBytes = archiveAvailableCapacityBytes
        self.projectedArchiveBytes = projectedArchiveBytes
    }
}

public enum VaultAutomationPostponement: Equatable, Sendable {
    case vaultDisabled
    case invalidPolicy
    case archiveCapacityUnavailable
    case insufficientArchiveCapacity
    case cubaseRunning
    case openFiles
    case recentWriteActivity
    case uncertainActivity(String)

    public var message: String {
        switch self {
        case .vaultDisabled: "Project Vault is turned off."
        case .invalidPolicy: "Check the Project Vault free-space settings."
        case .archiveCapacityUnavailable: "Available space could not be checked. Reconnect the destination drive and check folder access, then retry."
        case .insufficientArchiveCapacity: "There isn’t enough free space on the Vault drive for this project plus the spare room you set. Free up space and retry. Every copy was kept."
        case .cubaseRunning: "Close Cubase and Ableton Live before removing the Active copy."
        case .openFiles: "Close programs using files in this project and retry."
        case .recentWriteActivity: "Files in this project are still changing. Wait for saving to finish and retry."
        case .uncertainActivity(let reason): "Project activity could not be checked: \(reason). Existing copies were kept."
        }
    }

    public var permitsBoundedAutomaticRetry: Bool {
        switch self {
        case .cubaseRunning, .openFiles, .recentWriteActivity, .uncertainActivity:
            true
        default:
            false
        }
    }
}

public enum VaultAutomationEligibility: Equatable, Sendable {
    case eligible
    case postponed(VaultAutomationPostponement)
}

public struct VaultArchiveWriteAdmissionEvaluator: Sendable {
    private static let bytesPerGiB: Int64 = 1_073_741_824

    public init() {}

    public func postponement(
        availableCapacityBytes: Int64?,
        projectedCopyBytes: Int64?,
        minimumFreeSpaceGiB: Int
    ) -> VaultAutomationPostponement? {
        guard minimumFreeSpaceGiB >= 0,
              Int64(minimumFreeSpaceGiB) <= Int64.max / Self.bytesPerGiB else {
            return .invalidPolicy
        }
        guard let availableCapacityBytes,
              let projectedCopyBytes,
              availableCapacityBytes >= 0,
              projectedCopyBytes >= 0 else {
            return .archiveCapacityUnavailable
        }
        let minimumFreeBytes = Int64(minimumFreeSpaceGiB) * Self.bytesPerGiB
        let (requiredBytes, overflow) = projectedCopyBytes.addingReportingOverflow(minimumFreeBytes)
        guard !overflow, availableCapacityBytes >= requiredBytes else {
            return .insufficientArchiveCapacity
        }
        return nil
    }
}

public struct VaultAutomationEligibilityEvaluator: Sendable {
    public init() {}

    public func evaluate(
        _ candidate: VaultAutomationCandidate,
        policy: VaultAutomationPolicy
    ) -> VaultAutomationEligibility {
        guard policy.isVaultEnabled else { return .postponed(.vaultDisabled) }
        if let postponement = VaultArchiveWriteAdmissionEvaluator().postponement(
            availableCapacityBytes: candidate.archiveAvailableCapacityBytes,
            projectedCopyBytes: candidate.projectedArchiveBytes,
            minimumFreeSpaceGiB: policy.transferFreeSpaceReserveGiB
        ) {
            return .postponed(postponement)
        }
        return .eligible
    }
}

public enum VaultActivityStatus: Equatable, Sendable {
    case clear
    case busy
    case uncertain(String)
}

public protocol VaultAutomationActivityProbing: Sendable {
    /// Legacy API name; probes both Cubase and Ableton Live before any Vault mutation.
    func cubaseStatus() async -> VaultActivityStatus
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus
}

enum VaultActivityCommandStatus: Equatable, Sendable {
    case exited(Int32, output: String = "", hasDiagnostics: Bool = false)
    case timedOut
    case cancelled
    case unavailable
    case failed
}

protocol VaultActivityCommandRunning: Sendable {
    func status(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> VaultActivityCommandStatus
}

struct FoundationVaultActivityCommandRunner: VaultActivityCommandRunning {
    func status(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> VaultActivityCommandStatus {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return .unavailable }
        guard timeout > 0 else { return .timedOut }
        guard !Task.isCancelled else { return .cancelled }

        // A warning can make lsof exit 1 even when it found open files. Keep
        // bounded field output without retaining paths or risking a full pipe.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-activity-\(UUID().uuidString)", isDirectory: true)
        let outputURL = directory.appendingPathComponent("stdout")
        let diagnosticsURL = directory.appendingPathComponent("stderr")
        defer { try? FileManager.default.removeItem(at: directory) }
        let output: FileHandle
        let diagnostics: FileHandle
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try Data().write(to: outputURL)
            try Data().write(to: diagnosticsURL)
            output = try FileHandle(forWritingTo: outputURL)
            diagnostics = try FileHandle(forWritingTo: diagnosticsURL)
        } catch { return .failed }
        defer {
            try? output.close()
            try? diagnostics.close()
        }
        let execution = VaultActivityProcessExecution(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            output: output,
            diagnostics: diagnostics,
            outputURL: outputURL,
            diagnosticsURL: diagnosticsURL
        )
        return await withTaskCancellationHandler {
            await execution.start()
        } onCancel: {
            execution.cancel()
        }
    }
}

private final class VaultActivityProcessExecution: @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let timeout: TimeInterval
    private let output: FileHandle
    private let diagnostics: FileHandle
    private let outputURL: URL
    private let diagnosticsURL: URL
    private let lock = NSLock()
    private var process: Process?
    private var continuation: CheckedContinuation<VaultActivityCommandStatus, Never>?
    private var result: VaultActivityCommandStatus?
    private var timeoutWorkItem: DispatchWorkItem?

    init(executable: String, arguments: [String], timeout: TimeInterval,
         output: FileHandle, diagnostics: FileHandle, outputURL: URL, diagnosticsURL: URL) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
        self.output = output
        self.diagnostics = diagnostics
        self.outputURL = outputURL
        self.diagnosticsURL = diagnosticsURL
    }

    func start() async -> VaultActivityCommandStatus {
        await withCheckedContinuation { continuation in
            let pendingResult = lock.withLock { () -> VaultActivityCommandStatus? in
                self.continuation = continuation
                return result
            }
            if let pendingResult {
                continuation.resume(returning: pendingResult)
                return
            }
            launch()
        }
    }

    func cancel() {
        finish(.cancelled, terminateRunningProcess: true)
    }

    private func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = diagnostics
        process.terminationHandler = { [weak self] completedProcess in
            guard let self else { return }
            do {
                let outputSize = try self.outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let diagnosticsSize = try self.diagnosticsURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard let outputSize, let diagnosticsSize else {
                    self.finish(.failed, terminateRunningProcess: false)
                    return
                }
                guard outputSize <= 1_048_576,
                      let output = String(data: try Data(contentsOf: self.outputURL), encoding: .utf8) else {
                    self.finish(.failed, terminateRunningProcess: false)
                    return
                }
                self.finish(.exited(completedProcess.terminationStatus,
                                    output: output,
                                    hasDiagnostics: diagnosticsSize > 0), terminateRunningProcess: false)
            } catch {
                self.finish(.failed, terminateRunningProcess: false)
            }
        }

        let shouldLaunch = lock.withLock { result == nil }
        guard shouldLaunch else { return }

        do {
            try process.run()
        } catch {
            finish(.failed, terminateRunningProcess: false)
            return
        }

        let timedOut = DispatchWorkItem { [weak self] in
            self?.finish(.timedOut, terminateRunningProcess: true)
        }
        // Publish the process only after `run()` returns, so `finish` never
        // calls `terminate()` on a process that has not launched.
        let shouldScheduleTimeout = lock.withLock { () -> Bool in
            guard result == nil else { return false }
            self.process = process
            timeoutWorkItem = timedOut
            return true
        }
        if shouldScheduleTimeout {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timedOut)
        } else {
            process.terminate()
        }
    }

    private func finish(
        _ result: VaultActivityCommandStatus,
        terminateRunningProcess: Bool
    ) {
        let completion = lock.withLock { () -> (Process?, DispatchWorkItem?, CheckedContinuation<VaultActivityCommandStatus, Never>?)? in
            guard self.result == nil else { return nil }
            self.result = result
            let completion = (process, timeoutWorkItem, continuation)
            process = nil
            timeoutWorkItem = nil
            continuation = nil
            return completion
        }
        guard let (process, timeoutWorkItem, continuation) = completion else { return }
        timeoutWorkItem?.cancel()
        if terminateRunningProcess { process?.terminate() }
        continuation?.resume(returning: result)
    }
}

/// Production probe. Exit statuses other than the documented clear/busy values
/// are uncertainty and therefore postpone work.
public struct SystemVaultAutomationActivityProbe: VaultAutomationActivityProbing, @unchecked Sendable {
    private let fileManager: FileManager
    private let commandRunner: any VaultActivityCommandRunning
    private let activeUseProbeTimeout: TimeInterval

    public init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            commandRunner: FoundationVaultActivityCommandRunner(),
            activeUseProbeTimeout: 5
        )
    }

    init(
        fileManager: FileManager = .default,
        commandRunner: any VaultActivityCommandRunning,
        activeUseProbeTimeout: TimeInterval
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.activeUseProbeTimeout = max(0, activeUseProbeTimeout)
    }

    public func cubaseStatus() async -> VaultActivityStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return .uncertain("probe-failed-\(process.terminationStatus)")
            }
            return (CubaseProcessDetector.containsCubase(inProcessList: text)
                || AbletonProcessDetector.containsAbleton(inProcessList: text)) ? .busy : .clear
        } catch {
            return .uncertain("probe-failed")
        }
    }

    public func openFileStatus(in projectURL: URL) async -> VaultActivityStatus {
        let status = await commandRunner.status(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-w", "-F", "pft", "+D", projectURL.path],
            timeout: activeUseProbeTimeout
        )
        switch status {
        case .exited(let code, let output, let hasDiagnostics):
            if !output.isEmpty && !Self.containsOnlyOwnDirectoryHandles(output) { return .busy }
            guard !hasDiagnostics, code == 0 || code == 1 else {
                return .uncertain("probe-failed-\(code)")
            }
            return output.isEmpty && code == 0 ? .uncertain("probe-empty-success") : .clear
        case .timedOut: return .uncertain("probe-timed-out")
        case .cancelled: return .uncertain("probe-cancelled")
        case .unavailable: return .uncertain("probe-unavailable")
        case .failed: return .uncertain("probe-failed")
        }
    }

    /// Removal pins the source inode with our own directory descriptor. Ignore
    /// only those descriptors; our regular files and every other process count.
    private static func containsOnlyOwnDirectoryHandles(_ output: String) -> Bool {
        let fields = output.split(separator: "\n")
        guard fields.first == "p\(ProcessInfo.processInfo.processIdentifier)",
              fields.count >= 3, fields.count % 2 == 1 else { return false }
        for index in stride(from: 1, to: fields.count, by: 2) {
            let descriptor = fields[index]
            guard descriptor.first == "f", Int(descriptor.dropFirst()) != nil,
                  fields[index + 1] == "tDIR" else { return false }
        }
        return true
    }

    public func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus {
        guard fileManager.fileExists(atPath: projectURL.path) else { return .uncertain("project-missing") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(activeUseProbeTimeout))
        guard !Task.isCancelled else { return .uncertain("probe-cancelled") }
        guard ContinuousClock.now < deadline else { return .uncertain("probe-timed-out") }
        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsPackageDescendants]
        ) else { return .uncertain("project-unreadable") }

        do {
            while true {
                try checkActivityScanContinues(until: deadline)
                guard let url = enumerator.nextObject() as? URL else { break }
                try checkActivityScanContinues(until: deadline)
                if let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified >= since {
                    return .busy
                }
            }
            return .clear
        } catch is CancellationError {
            return .uncertain("probe-cancelled")
        } catch is VaultActivityProbeError {
            return .uncertain("probe-timed-out")
        } catch {
            return .uncertain("metadata-unreadable")
        }
    }

    private func checkActivityScanContinues(until deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw VaultActivityProbeError.timedOut }
    }
}

private enum VaultActivityProbeError: Error {
    case timedOut
}

struct AbletonProcessDetector: Sendable {
    static func containsAbleton(inProcessList text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(fileURLWithPath: path)
            // The macOS executable is Live inside an Ableton Live <version> app bundle.
            return url.lastPathComponent == "Live"
                && url.deletingLastPathComponent().lastPathComponent == "MacOS"
                && url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents"
                && url.pathComponents.contains { $0.hasPrefix("Ableton Live ") && $0.hasSuffix(".app") }
        }
    }
}

struct CubaseProcessDetector: Sendable {
    static func containsCubase(inProcessList text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            isCubaseExecutable(String(line))
        }
    }

    static func isCubaseExecutable(_ command: String) -> Bool {
        let executable = URL(fileURLWithPath: command.trimmingCharacters(in: .whitespacesAndNewlines))
            .lastPathComponent
        let components = executable.split(separator: " ", omittingEmptySubsequences: true)
        guard components.first == "Cubase" else { return false }
        guard components.count > 1 else { return true }
        let version = components.dropFirst().joined(separator: " ")
        return version.contains(where: \.isNumber)
            && version.allSatisfy { $0.isNumber || $0 == "." }
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
    case pending(ProjectID, VaultTransferRecord)
    case failed(VaultAutomationFailureNotification)
}

/// Runs the Done archive: the Vault and capacity checks, the activity probes,
/// the copy, and — only when the caller says the run removes the Active copy —
/// the probes again and the removal. A busy or uncertain probe after the copy
/// keeps both copies. Postponements and failures come back as results.
public actor VaultAutomationScheduler {
    private let policy: VaultAutomationPolicy
    private let evaluator: VaultAutomationEligibilityEvaluator
    private let activityProbe: any VaultAutomationActivityProbing
    private let archiver: any VaultAutomaticArchiving
    private let now: @Sendable () -> Date
    private let removesActiveCopy: Bool

    public init(
        policy: VaultAutomationPolicy,
        activityProbe: any VaultAutomationActivityProbing,
        archiver: any VaultAutomaticArchiving,
        removesActiveCopy: Bool,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.policy = policy
        self.evaluator = VaultAutomationEligibilityEvaluator()
        self.activityProbe = activityProbe
        self.archiver = archiver
        self.removesActiveCopy = removesActiveCopy
        self.now = now
    }

    /// Throws `CancellationError` or `VaultTransferInterruption` when the
    /// archive is stopped; every other error becomes a `.failed` result.
    public func run(candidates: [VaultAutomationCandidate]) async throws -> [VaultAutomationRunResult] {
        var results: [VaultAutomationRunResult] = []
        for candidate in candidates {
            let eligibility = evaluator.evaluate(candidate, policy: policy)
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
                if archived.isWaitingForProviderUpload {
                    results.append(.pending(candidate.projectID, archived))
                    continue
                }
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
            } catch let admission as VaultWriteAdmissionError {
                switch admission {
                case .postponed(let reason):
                    results.append(.postponed(candidate.projectID, reason))
                }
            } catch is CancellationError {
                // A stop is not a failure: end the pass and let callers see it.
                throw CancellationError()
            } catch let interruption as VaultTransferInterruption {
                throw interruption
            } catch {
                let failure = VaultAutomationFailureNotification(
                    projectID: candidate.projectID,
                    stage: "automatic-archive",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
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
