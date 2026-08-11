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

    private weak var host: (any ArchiveScanHost)?
    private var activeScanGeneration: UInt64?
    /// Owns the async full-scan request rather than only its generation marker, so
    /// a root replacement can stop the underlying detached filesystem traversal.
    private var activeFullScanTask: Task<ScanResult, Error>?
    private var pendingIncrementalPaths: Set<String> = []
    private var fullRescanPending = false

    init(host: any ArchiveScanHost) {
        self.host = host
    }

    func invalidateForRootChange() {
        activeFullScanTask?.cancel()
        activeFullScanTask = nil
        activeScanGeneration = nil
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
            let result = try await withTaskCancellationHandler(operation: {
                try await scanTask.value
            }, onCancel: {
                scanTask.cancel()
            })
            try applyFullScanResult(result, request: request, scannedAt: scannedAt)
        } catch is CancellationError {
            guard isCurrentScan(request) else { return }
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
        let batch = pendingIncrementalPaths
        pendingIncrementalPaths.removeAll(keepingCapacity: true)
        await rescanChangedPaths(batch.map { URL(fileURLWithPath: $0) })
    }

    private func rescanChangedPaths(_ changedPaths: [URL]) async {
        guard let host else { return }
        guard !host.roots.isEmpty, !changedPaths.isEmpty, !host.isScanning else { return }
        host.isScanning = true
        defer {
            // Full scans own `isScanning` via `activeScanGeneration`; a stale incremental
            // completion must not clear the flag while a newer full scan is still running.
            if activeScanGeneration == nil {
                host.isScanning = false
            }
            Task { await drainPendingIncrementalRescan() }
        }

        #if DEBUG
        if let holdRaw = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_TEST_INCREMENTAL_HOLD_NS"],
           let holdNanoseconds = UInt64(holdRaw), holdNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: holdNanoseconds)
        }
        #endif

        let rootsSnapshot = host.roots
        let generationSnapshot = host.rootGeneration
        do {
            guard let update = try await host.catalog.applyIncrementalFilesystemUpdate(
                changedPaths: changedPaths,
                roots: rootsSnapshot,
                existingSongs: host.scannedSongs,
                collaborators: host.collaborators,
                priorDiagnostics: host.scanDiagnostics
            ) else { return }

            guard host.rootGeneration == generationSnapshot,
                  host.roots.standardizedArchivePaths == rootsSnapshot.standardizedArchivePaths else { return }

            host.applyCatalogScanUpdate(update.catalogApplyResult, roots: rootsSnapshot)
            host.diagnostics.log(.info, "Incremental archive rescan updated \(update.incrementalSongCount) song(s)")
        } catch is CancellationError {
            return
        } catch {
            guard host.rootGeneration == generationSnapshot,
                  host.roots.standardizedArchivePaths == rootsSnapshot.standardizedArchivePaths else { return }
            host.setBackgroundStatusMessage("Incremental rescan failed: \(error.localizedDescription)")
            host.diagnostics.log(.error, "Incremental archive rescan failed: \(error)")
        }
    }
}
