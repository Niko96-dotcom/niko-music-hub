import AppCore
import Foundation
import NikoMusicCore

extension [URL] {
    var standardizedArchivePaths: [String] {
        map { $0.standardizedFileURL.path }
    }
}

/// Unified full and incremental archive scan lifecycle. Owned by ``ArchiveBrowserViewModel``.
@MainActor
protocol ArchiveScanHost: AnyObject {
    var roots: [URL] { get }
    /// Scanner-owned baseline. This intentionally excludes opt-in Project Vault
    /// archive projections which can appear in the visible `songs` catalog.
    var scannedSongs: [Song] { get }
    var collaborators: [Collaborator] { get }
    var scanDiagnostics: ArchiveScanDiagnostics? { get }
    var rootGeneration: UInt64 { get }
    var isScanning: Bool { get set }
    var catalog: ArchiveCatalogCoordinator { get }
    var diagnostics: Diagnostics { get }
    var archiveRootWatcher: (any ArchiveRootWatching)? { get }
    var scanOverride: (([URL]) async throws -> ScanResult)? { get }
    /// Test seam: awaited after an incremental rescan has claimed `isScanning` and
    /// before it reads the filesystem, so a test can hold the scan in flight.
    var incrementalRescanHold: (() async -> Void)? { get }

    func mutateCatalog(_ updates: () -> Void)
    func setStatusMessage(_ message: String?)
    func setBackgroundStatusMessage(_ message: String?)
    func applyCatalogScanUpdate(_ update: ArchiveCatalogCoordinator.CatalogScanApplyResult, roots: [URL])
    func applyScanFailure(_ error: Error)
}

@MainActor
final class ArchiveScanOrchestrator {
    private static let maximumPendingIncrementalPathCount = 1_024

    private struct ScanRequest {
        let roots: [URL]
        let generation: UInt64
    }

    private struct IncrementalRequest {
        let id: UInt64
        let roots: [URL]
        let generation: UInt64
    }

    private weak var host: (any ArchiveScanHost)?
    private var activeScanGeneration: UInt64?
    /// Owns the async full-scan request rather than only its generation marker, so
    /// a root replacement can stop the underlying detached filesystem traversal.
    private var activeFullScanTask: Task<ScanResult, Error>?
    private var pendingIncrementalPaths: Set<String> = []
    private var fullRescanPending = false
    private var userCancelRequested = false
    /// Monotonic id for each incremental batch. The in-flight batch owns `isScanning`
    /// via `activeIncrementalGeneration`.
    private var nextIncrementalGeneration: UInt64 = 0
    private var activeIncrementalGeneration: UInt64?
    /// Retains the in-flight incremental filesystem operation so user cancel and
    /// root replacement stop its detached scan (via `withTaskCancellationHandler`
    /// in `performIncrementalScanDetached`), not merely suppress publication.
    /// Cleared only by its owner (id match) so a newer batch is never dropped.
    /// A new scan never awaits an old task: cancellation is fire-and-forget and
    /// the watermark below remains the defense against a noncooperative batch.
    private var activeIncrementalTask: Task<ArchiveCatalogCoordinator.IncrementalFilesystemApplyResult?, Error>?
    private var activeIncrementalTaskID: UInt64?
    /// High-water mark of user-canceled incremental batches. A cancel records the
    /// in-flight batch id here — never by clearing a shared boolean the held scan may
    /// not have observed yet — so the resumed batch still knows it was canceled while
    /// a newer batch (larger id) started afterwards is unaffected.
    private var canceledIncrementalThrough: UInt64 = 0

    init(host: any ArchiveScanHost) {
        self.host = host
    }

    func cancelActiveScan() {
        userCancelRequested = true
        activeFullScanTask?.cancel()
        activeIncrementalTask?.cancel()
        if activeScanGeneration != nil {
            // A full scan owns `isScanning`; it consumes `userCancelRequested` itself.
            return
        }
        if let canceled = activeIncrementalGeneration {
            canceledIncrementalThrough = max(canceledIncrementalThrough, canceled)
            activeIncrementalGeneration = nil
            pendingIncrementalPaths.removeAll()
            fullRescanPending = false
            if let host, host.isScanning {
                host.isScanning = false
                host.setStatusMessage(CancelCopy.scanCanceled)
            }
        } else {
            // No tracked owner: drop queued (but unstarted) watcher work so a drain
            // that has not run yet cannot start canceled work. `isScanning` is
            // released so replacement work can start immediately.
            pendingIncrementalPaths.removeAll()
            fullRescanPending = false
            if let host, host.isScanning {
                host.isScanning = false
                host.setStatusMessage(CancelCopy.scanCanceled)
            }
        }
    }

    func invalidateForRootChange() {
        userCancelRequested = false
        activeFullScanTask?.cancel()
        activeFullScanTask = nil
        activeScanGeneration = nil
        activeIncrementalTask?.cancel()
        activeIncrementalTask = nil
        activeIncrementalTaskID = nil
        activeIncrementalGeneration = nil
        pendingIncrementalPaths.removeAll()
        fullRescanPending = false
    }

    func clearPendingPaths() {
        pendingIncrementalPaths.removeAll()
        fullRescanPending = false
    }

    func restartArchiveRootWatching() {
        guard let host else { return }
        guard let archiveRootWatcher = host.archiveRootWatcher else { return }
        let rootsSnapshot = host.roots
        let started = archiveRootWatcher.setRoots(rootsSnapshot) { [weak self] event in
            guard let self else { return }
            guard let host = self.host, !host.roots.isEmpty else { return }
            switch event {
            case .paths(let changedPaths):
                self.enqueueIncrementalRescan(paths: changedPaths)
            case .fullRescanRequired:
                self.enqueueFullRescan()
            }
        }
        if !started {
            host.diagnostics.log(
                .error,
                "Archive filesystem watcher could not start; incremental rescans are disabled until the next root change."
            )
            host.setBackgroundStatusMessage(
                "Archive filesystem watcher unavailable — use Rescan to refresh after external edits."
            )
        }
    }

    func scan() async {
        await runFullScan(isBackground: false)
    }

    func scanInBackground() async {
        await runFullScan(isBackground: true)
    }

    func scanSync() {
        guard let host else { return }
        runFullScanSync(isBackground: false) { roots in
            try host.catalog.performScanSynchronously(roots: roots)
        }
    }

    private func runFullScan(isBackground: Bool) async {
        guard let request = beginScan(isBackground: isBackground) else { return }
        defer { finishScan(request) }
        do {
            let scannedAt = Date()
            let scanTask = Task { @MainActor [weak self] () throws -> ScanResult in
                guard let self else { throw CancellationError() }
                return try await self.performScanDetached(roots: request.roots)
            }
            activeFullScanTask = scanTask
            if userCancelRequested {
                scanTask.cancel()
            }
            let result = try await withTaskCancellationHandler(operation: {
                try await scanTask.value
            }, onCancel: {
                scanTask.cancel()
            })
            try applyFullScanResult(result, request: request, scannedAt: scannedAt)
        } catch is CancellationError {
            guard isCurrentScan(request) else { return }
            if userCancelRequested {
                host?.setStatusMessage(CancelCopy.scanCanceled)
                userCancelRequested = false
            }
        } catch {
            guard isCurrentScan(request) else { return }
            recordScanFailure(error)
        }
    }

    private func runFullScanSync(
        isBackground: Bool,
        _ perform: ([URL]) throws -> ScanResult
    ) {
        guard let request = beginScan(isBackground: isBackground) else { return }
        defer { finishScan(request) }
        do {
            let scannedAt = Date()
            let result = try perform(request.roots)
            try applyFullScanResult(result, request: request, scannedAt: scannedAt)
        } catch {
            guard isCurrentScan(request) else { return }
            recordScanFailure(error)
        }
    }

    private func applyFullScanResult(
        _ result: ScanResult,
        request: ScanRequest,
        scannedAt: Date
    ) throws {
        guard let host, isCurrentScan(request) else { return }
        let update = host.catalog.applyFullScanResult(
            result: result,
            roots: request.roots,
            collaborators: host.collaborators,
            scannedAt: scannedAt
        )
        host.applyCatalogScanUpdate(update, roots: request.roots)
        host.diagnostics.log(.info, update.diagnostics.summaryLine)
    }

    private func beginScan(isBackground: Bool) -> ScanRequest? {
        guard let host else { return nil }
        guard !host.roots.isEmpty else {
            if isBackground {
                host.setBackgroundStatusMessage("Add at least one archive root.")
            } else {
                host.setStatusMessage("Add at least one archive root.")
            }
            return nil
        }
        guard !host.isScanning else { return nil }
        userCancelRequested = false
        host.isScanning = true
        activeScanGeneration = host.rootGeneration
        if isBackground {
            host.setBackgroundStatusMessage("Scanning archive...")
        } else {
            host.setStatusMessage("Scanning archive...")
        }
        return ScanRequest(roots: host.roots, generation: host.rootGeneration)
    }

    private func finishScan(_ request: ScanRequest) {
        guard let host else { return }
        guard activeScanGeneration == request.generation else { return }
        activeFullScanTask = nil
        activeScanGeneration = nil
        host.isScanning = false
        Task { await drainPendingIncrementalRescan() }
    }

    private func isCurrentScan(_ request: ScanRequest) -> Bool {
        guard let host else { return false }
        return activeScanGeneration == request.generation
            && host.rootGeneration == request.generation
            && host.roots.standardizedArchivePaths == request.roots.standardizedArchivePaths
    }

    private func recordScanFailure(_ error: Error) {
        host?.applyScanFailure(error)
    }

    private func performScanDetached(roots: [URL]) async throws -> ScanResult {
        guard let host else {
            throw CancellationError()
        }
        if let scanOverride = host.scanOverride {
            let result = try await scanOverride(roots)
            try Task.checkCancellation()
            return result
        }
        return try await host.catalog.performScanDetached(roots: roots)
    }

    private func enqueueIncrementalRescan(paths: [URL]) {
        guard !paths.isEmpty, !fullRescanPending else { return }
        for path in paths {
            let standardizedPath = path.standardizedFileURL.path
            guard !pendingIncrementalPaths.contains(standardizedPath) else { continue }
            guard pendingIncrementalPaths.count < Self.maximumPendingIncrementalPathCount else {
                enqueueFullRescan()
                return
            }
            pendingIncrementalPaths.insert(standardizedPath)
        }
        schedulePendingRescanDrainIfIdle()
    }

    private func enqueueFullRescan() {
        pendingIncrementalPaths.removeAll(keepingCapacity: true)
        guard !fullRescanPending else { return }
        fullRescanPending = true
        schedulePendingRescanDrainIfIdle()
    }

    private func schedulePendingRescanDrainIfIdle() {
        guard let host, !host.isScanning else { return }
        Task { await drainPendingIncrementalRescan() }
    }

    private func drainPendingIncrementalRescan() async {
        guard let host, !host.isScanning else { return }
        if fullRescanPending {
            fullRescanPending = false
            host.diagnostics.log(
                .warning,
                "Archive filesystem watcher requested a full rescan after incomplete event delivery."
            )
            await runFullScan(isBackground: true)
            return
        }
        guard !pendingIncrementalPaths.isEmpty else { return }
        // Snapshot roots/generation BEFORE the batch can park at the test hold, so a
        // root change during the hold is detectable when the batch resumes.
        nextIncrementalGeneration &+= 1
        let request = IncrementalRequest(
            id: nextIncrementalGeneration,
            roots: host.roots,
            generation: host.rootGeneration
        )
        let batch = pendingIncrementalPaths
        pendingIncrementalPaths.removeAll(keepingCapacity: true)
        await rescanChangedPaths(batch.map { URL(fileURLWithPath: $0) }, request: request)
    }

    private func rescanChangedPaths(_ changedPaths: [URL], request: IncrementalRequest) async {
        guard let host else { return }
        guard !request.roots.isEmpty, !changedPaths.isEmpty, !host.isScanning else { return }
        activeIncrementalGeneration = request.id
        host.isScanning = true
        defer {
            // Only the owning batch clears `isScanning` or chains another drain: a
            // canceled (or root-replaced) batch must not clear a newer scan's state
            // or drain work it did not queue. Full scans own `isScanning` via
            // `activeScanGeneration`; a stale incremental completion must not clear
            // the flag while a newer full scan is still running either.
            let isOwner = activeIncrementalGeneration == request.id
            if isOwner {
                activeIncrementalGeneration = nil
            }
            if isOwner, activeScanGeneration == nil {
                host.isScanning = false
            }
            // The task handle uses its own id check so a stale completion never
            // clears a newer batch's handle, while a canceled batch without a
            // successor still releases its own handle.
            if activeIncrementalTaskID == request.id {
                activeIncrementalTask = nil
                activeIncrementalTaskID = nil
            }
            host.diagnostics.log(.info, "Incremental archive rescan finished")
            if isOwner {
                Task { await drainPendingIncrementalRescan() }
            }
        }

        if let hold = host.incrementalRescanHold {
            await hold()
        }
        // A user cancel (or root replacement) while held released ownership above;
        // the watermark survives so this resumed batch still knows it was canceled.
        // The cancel already published its status synchronously, so discard quietly.
        guard canceledIncrementalThrough < request.id else { return }
        guard host.rootGeneration == request.generation,
              host.roots.standardizedArchivePaths == request.roots.standardizedArchivePaths else {
            host.diagnostics.log(.info, "Incremental archive rescan discarded: roots changed while it ran")
            return
        }

        do {
            // Retain the actual filesystem operation so cancel/root-change reaches
            // its `withTaskCancellationHandler` and stops the detached scan.
            // Pending watcher coalescing and root generation checks below are
            // unchanged; the watermark remains the defense for noncooperative work.
            let catalogSnapshot = host.catalog
            let changedSnapshot = changedPaths
            let rootsSnapshot = request.roots
            let existingSnapshot = host.scannedSongs
            let collaboratorsSnapshot = host.collaborators
            let priorSnapshot = host.scanDiagnostics
            let operationTask = Task { @MainActor () throws -> ArchiveCatalogCoordinator.IncrementalFilesystemApplyResult? in
                try await catalogSnapshot.applyIncrementalFilesystemUpdate(
                    changedPaths: changedSnapshot,
                    roots: rootsSnapshot,
                    existingSongs: existingSnapshot,
                    collaborators: collaboratorsSnapshot,
                    priorDiagnostics: priorSnapshot
                )
            }
            activeIncrementalTask = operationTask
            activeIncrementalTaskID = request.id
            // A cancel or root replacement landing between the pre-scan guards and
            // the handle retain still stops I/O instead of running stale work.
            if canceledIncrementalThrough >= request.id
                || host.rootGeneration != request.generation
                || host.roots.standardizedArchivePaths != request.roots.standardizedArchivePaths {
                operationTask.cancel()
            }
            guard let update = try await withTaskCancellationHandler(operation: {
                try await operationTask.value
            }, onCancel: {
                operationTask.cancel()
            }) else { return }

            guard canceledIncrementalThrough < request.id,
                  activeIncrementalGeneration == request.id,
                  host.rootGeneration == request.generation,
                  host.roots.standardizedArchivePaths == request.roots.standardizedArchivePaths else {
                host.diagnostics.log(.info, "Incremental archive rescan discarded: superseded while it ran")
                return
            }

            host.applyCatalogScanUpdate(update.catalogApplyResult, roots: request.roots)
            host.diagnostics.log(.info, "Incremental archive rescan updated \(update.incrementalSongCount) song(s)")
        } catch is CancellationError {
            return
        } catch {
            guard canceledIncrementalThrough < request.id,
                  activeIncrementalGeneration == request.id,
                  host.rootGeneration == request.generation,
                  host.roots.standardizedArchivePaths == request.roots.standardizedArchivePaths else { return }
            host.setBackgroundStatusMessage("Incremental rescan failed: \(error.localizedDescription)")
            host.diagnostics.log(.error, "Incremental archive rescan failed: \(error)")
        }
    }
}
