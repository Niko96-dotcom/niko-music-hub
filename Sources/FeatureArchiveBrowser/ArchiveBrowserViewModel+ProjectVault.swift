import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func projectVaultPresentation(for song: Song) -> ProjectVaultCardPresentation? {
        guard let settings = try? settingsStore.loadSettings(), settings.vault.isEnabled else { return nil }
        let path = song.folderPath.standardizedFileURL.resolvingSymlinksInPath()
        let matchingRoot = settings.musicRoots.first { root in
            guard root.role == .active || root.role == .archive else { return false }
            return Self.vaultContains(root.fallbackURL, path)
        }
        guard let matchingRoot else { return nil }
        let kind: LocationKind = matchingRoot.role == .active ? .active : .archive
        let record = ProjectRecord(
            canonicalTitle: song.effectiveDisplayTitle,
            locations: [ProjectLocation(rootID: matchingRoot.id, relativePath: song.folderPath.lastPathComponent, kind: kind)],
            pinned: settings.vault.keepLocalProjectIDs.contains(song.id),
            workflowState: song.workflowStatus,
            lastActivityAt: song.effectiveLatestCPR?.modifiedAt
        )
        return ProjectVaultCardPresentation(record: record)
    }

    func setProjectKeepLocal(_ keepLocal: Bool, for song: Song) {
        do {
            try settingsStore.updateSettings { settings in
                if keepLocal { settings.vault.keepLocalProjectIDs.insert(song.id) }
                else { settings.vault.keepLocalProjectIDs.remove(song.id) }
            }
            objectWillChange.send()
        } catch {
            diagnostics.log(.error, "Project Vault Keep Local setting failed: \(error)")
            setStatusMessage("Keep Local could not be saved. No project files were changed.")
        }
    }

    /// Active projects retain the existing safe opener. Archive-only projects fail
    /// closed until a verified stable catalog generation can be resolved by runtime wiring.
    func performProjectVaultPrimaryAction(for song: Song) {
        guard let presentation = projectVaultPresentation(for: song) else {
            try? openLatestCPR(for: song)
            return
        }
        switch presentation.primaryAction {
        case .openInCubase:
            try? openLatestCPR(for: song)
        case .restoreAndOpen:
            setStatusMessage("Restore is paused: a verified Project Vault generation could not be resolved. No files were changed.")
            diagnostics.log(.warning, "Project Vault restore refused without a verified runtime catalog generation")
        case .review:
            setStatusMessage(presentation.explanation)
        }
    }

    private static func vaultContains(_ root: URL, _ candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
