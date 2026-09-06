import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func canRecoverInterruptedProject(_ song: Song) -> Bool {
        guard let transfer = projectVaultSnapshot(for: song)?.transfer,
              transfer.state == .recoveryRequired, let origin = transfer.error?.origin else { return false }
        return [.removingActiveCopy, .evictingProviderCache].contains(origin)
    }

    func recoverInterruptedProject(_ song: Song) {
        guard canRecoverInterruptedProject(song), let runtime = projectVaultRuntime,
              let snapshot = projectVaultSnapshot(for: song) else { return }
        enqueueProjectVaultOperation(for: song, label: "Recover", startMessage: "Verifying the archive and preserving existing Active files…") { model in
            do {
                _ = try await model.waitForProjectVaultSlot {
                    try await runtime.recoverInterruptedArchive(snapshot: snapshot)
                }
                await model.refreshProjectVaultSnapshots()
                await model.scan()
                model.setProjectVaultStatusMessage("Recovered and verified in Active Projects. Any previous Active folder was preserved; use Reveal Preserved Files in song details.")
                return true
            } catch {
                await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage("Recovery stopped safely: \(error.localizedDescription) Existing copies were kept.")
                return false
            }
        }
    }

    func preservedProjectVaultCopy(for song: Song) -> URL? {
        guard let transfer = projectVaultSnapshot(for: song)?.transfer,
              let active = projectVaultPresentationContext?.activeRoot,
              let root = try? active.resolvedURL(using: FoundationSecurityScopedBookmarks()) else { return nil }
        let recoveryRoot = root.appendingPathComponent(".niko-recovery", isDirectory: true)
            .appendingPathComponent(transfer.id.uuidString.lowercased(), isDirectory: true)
        let safety = PathSafety()
        guard safety.isResolvedContainedWithoutNestedSymlinks(recoveryRoot, in: root) else { return nil }
        return transfer.preservedActiveCopies?.reversed().first {
            safety.isResolvedContainedWithoutNestedSymlinks($0, in: recoveryRoot)
                && $0 != recoveryRoot && FileManager.default.fileExists(atPath: $0.path)
        }
    }

    func revealPreservedProjectVaultCopy(for song: Song) {
        guard let url = preservedProjectVaultCopy(for: song) else { return }
        fileActions.revealInFinder(url)
    }
}
