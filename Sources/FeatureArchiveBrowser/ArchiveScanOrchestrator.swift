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
    var songs: [Song] { get }
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
    func applyCatalogScanUpdate(_ update: ArchiveCatalogCoordinator.CatalogScanApplyResult, roots: [URL])
    func applyScanFailure(_ error: Error)
}

@MainActor
final class ArchiveScanOrchestrator {
    private struct ScanRequest {
        let roots: [URL]
        let generation: UInt64
    }

    private weak var host: (any ArchiveScanHost)?
    private var activeScanGeneration: UInt64?
    private var pendingIncrementalPaths: Set<String> = []

    init(host: any ArchiveScanHost) {
        self.host = host
    }

    func invalidateForRootChange() {
        activeScanGeneration = nil
        pendingIncrementalPaths.removeAll()
    }

    func clearPendingPaths() {
        pendingIncrementalPaths.removeAll()
    }

    func restartArchiveRootWatching() {
        guard let host else { return }
        guard let archiveRootWatcher = host.archiveRootWatcher else { return }
        let rootsSnapshot = host.roots
        archiveRootWatcher.setRoots(rootsSnapshot) { [weak self] changedPaths in
            guard let self else { return }
            guard let host = self.host, !host.roots.isEmpty else { return }
            self.enqueueIncrementalRescan(paths: changedPaths)
        }
    }

    func scan() async {
        await runFullScan { roots in try await performScanDetached(roots: roots) }
    }

    func scanSync() {
        guard let host else { return }
        runFullScanSync { roots in try host.catalog.performScanSynchronously(roots: roots) }
    }

    private func runFullScan(
        _ perform: ([URL]) async throws -> ScanResult
    ) async {
        guard let request = beginScan() else { return }
        defer { finishScan(request) }
        do {
            let scannedAt = Date()
            let result = try await perform(request.roots)
            try applyFullScanResult(result, request: request, scannedAt: scannedAt)
        } catch {
            guard isCurrentScan(request) else { return }
            recordScanFailure(error)
        }
    }

    private func runFullScanSync(
        _ perform: ([URL]) throws -> ScanResult
    ) {
        guard let request = beginScan() else { return }
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

    private func beginScan() -> ScanRequest? {
        guard let host else { return nil }
        guard !host.roots.isEmpty else {
            host.setStatusMessage("Add at least one archive root.")
            return nil
        }
        guard !host.isScanning else { return nil }
        host.isScanning = true
        activeScanGeneration = host.rootGeneration
        host.setStatusMessage("Scanning archive...")
        return ScanRequest(roots: host.roots, generation: host.rootGeneration)
    }

    private func finishScan(_ request: ScanRequest) {
        guard let host else { return }
        guard activeScanGeneration == request.generation else { return }
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
            return try await scanOverride(roots)
        }
        return try await host.catalog.performScanDetached(roots: roots)
    }

    private func enqueueIncrementalRescan(paths: [URL]) {
        pendingIncrementalPaths.formUnion(paths.map { $0.standardizedFileURL.path })
        guard let host, !host.isScanning else { return }
        Task { await drainPendingIncrementalRescan() }
    }

    private func drainPendingIncrementalRescan() async {
        guard let host, !host.isScanning, !pendingIncrementalPaths.isEmpty else { return }
        let batch = pendingIncrementalPaths
        pendingIncrementalPaths.removeAll()
        await rescanChangedPaths(batch.map { URL(fileURLWithPath: $0) })
    }

    private func rescanChangedPaths(_ changedPaths: [URL]) async {
        guard let host else { return }
        guard !host.roots.isEmpty, !changedPaths.isEmpty, !host.isScanning else { return }
        host.isScanning = true
        defer {
            host.isScanning = false
            Task { await drainPendingIncrementalRescan() }
        }

        let rootsSnapshot = host.roots
        let generationSnapshot = host.rootGeneration
        do {
            guard let update = try await host.catalog.applyIncrementalFilesystemUpdate(
                changedPaths: changedPaths,
                roots: rootsSnapshot,
                existingSongs: host.songs,
                collaborators: host.collaborators,
                priorDiagnostics: host.scanDiagnostics
            ) else { return }

            guard host.rootGeneration == generationSnapshot,
                  host.roots.standardizedArchivePaths == rootsSnapshot.standardizedArchivePaths else { return }

            host.applyCatalogScanUpdate(update.catalogApplyResult, roots: rootsSnapshot)
            host.diagnostics.log(.info, "Incremental archive rescan updated \(update.incrementalSongCount) song(s)")
        } catch {
            host.setStatusMessage("Incremental rescan failed: \(error.localizedDescription)")
            host.diagnostics.log(.error, "Incremental archive rescan failed: \(error)")
        }
    }
}
