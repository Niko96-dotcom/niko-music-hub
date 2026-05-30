import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func clearScanResults() {
        mutateCatalog {
            songs = []
            scanDiagnostics = nil
            selectedSong = nil
            statusMessage = nil
        }
    }

    func scan() async {
        guard let rootsSnapshot = beginScan() else { return }
        defer { isScanning = false }
        do {
            let scannedAt = Date()
            let scanner = scanner
            let result = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(roots: rootsSnapshot)
            }.value
            applyScanResult(result, roots: rootsSnapshot, scannedAt: scannedAt)
        } catch {
            recordScanFailure(error)
        }
    }

    func scanSync() {
        guard let rootsSnapshot = beginScan() else { return }
        defer { isScanning = false }
        do {
            let result = try scanner.scan(roots: rootsSnapshot)
            applyScanResult(result, roots: rootsSnapshot, scannedAt: Date())
        } catch {
            recordScanFailure(error)
        }
    }

    func beginScan() -> [URL]? {
        guard !roots.isEmpty else {
            statusMessage = "Add at least one archive root."
            return nil
        }
        guard !isScanning else { return nil }
        isScanning = true
        return roots
    }

    func recordScanFailure(_ error: Error) {
        mutateCatalog {
            scanDiagnostics = nil
            statusMessage = "Scan failed: \(error.localizedDescription)"
        }
        diagnostics.log(.error, statusMessage ?? "scan failed")
    }

    func applyScanResult(_ result: ScanResult, roots: [URL], scannedAt: Date) {
        let built = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: roots,
            scannedAt: scannedAt
        )
        mutateCatalog {
            songs = mergeUserMetadata(into: result.songs)
            scanDiagnostics = built
            statusMessage = built.compactSummaryLine
        }
        diagnostics.log(.info, built.summaryLine)
        persistCachedIndex(roots: roots, scannedAt: scannedAt)
        persistUserMetadata(for: songs)
    }

    func loadCachedIndexIfAvailable() {
        guard let archiveIndexStore else { return }
        guard let snapshot = try? archiveIndexStore.loadLatest() else { return }
        guard snapshot.matchesCurrentRoots(roots), !snapshot.songs.isEmpty else { return }
        mutateCatalog {
            songs = mergeUserMetadata(into: snapshot.songs)
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: snapshot.scannedAt, relativeTo: Date())
            statusMessage = "Loaded \(snapshot.songs.count) songs from cache (\(relative)). Scan to refresh."
        }
    }

    func persistCachedIndex(roots: [URL], scannedAt: Date) {
        guard let archiveIndexStore else { return }
        let snapshot = ArchiveIndexSnapshot(
            roots: roots.map { $0.standardizedFileURL.path },
            songs: songs,
            scannedAt: scannedAt
        )
        do {
            try archiveIndexStore.save(snapshot)
        } catch {
            diagnostics.log(.error, "Archive cache save failed: \(error)")
        }
    }

    func restartArchiveRootWatching() {
        guard let archiveRootWatcher else { return }
        let rootsSnapshot = roots
        archiveRootWatcher.setRoots(rootsSnapshot) { [weak self] in
            guard let self else { return }
            guard !self.isScanning, !self.roots.isEmpty else { return }
            Task { await self.scan() }
        }
    }
}
