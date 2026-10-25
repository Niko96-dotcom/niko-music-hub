import AppCore
import Foundation
import NikoMusicCore
import ProjectVaultRuntime

extension ArchiveBrowserViewModel {
    /// Persisted reviews carry no authorization. They resolve stable catalog
    /// identity/locations only and never invent a confirmation or queued archive.
    /// `trigger` stays nil here; only a current initiating song (see
    /// `beginIdentityReview`) may earn a fresh confirmation after stable re-resolution.
    func presentPendingIdentityReviewsIfNeeded() {
        guard vaultDialogs.identityReviewPresentation == nil else { return }
        identityReviewViewModel.reloadFromStore()
        guard let review = identityReviewViewModel.pendingReviews.first else { return }
        vaultDialogs.presentIdentityReview(ProjectIdentityReviewPresentation(
            review: review,
            title: titleForIdentityReview(review),
            song: stableSongForIdentityReview(review),
            trigger: nil
        ))
    }

    func beginIdentityReview(
        for song: Song,
        title: String,
        reason: String,
        trigger: ProjectVaultArchiveTrigger
    ) async {
        let review: ProjectIdentityReview
        if let pending = await projectVaultRuntime?.consumePendingIdentityReview() {
            review = pending
        } else {
            review = ProjectIdentityReview(
                existingProjectID: ProjectID(),
                candidateProjectID: ProjectID(),
                reason: reason
            )
        }
        identityReviewViewModel.adopt(review)
        vaultDialogs.presentIdentityReview(ProjectIdentityReviewPresentation(
            review: review,
            title: title,
            song: song,
            trigger: trigger
        ))
    }

    /// Safety invariant: identity resolution itself NEVER initiates archival.
    /// A persisted review (trigger == nil) only resolves identity. A current
    /// initiating song that still resolves by stable location/id evidence earns
    /// a fresh explicit confirmation. Persistence failure keeps the sheet visible
    /// and retryable; anything else that fails to resolve queues/confirms nothing.
    func resolvePresentedIdentityReview(as resolution: ProjectIdentityReviewResolution) {
        guard let presentation = vaultDialogs.identityReviewPresentation else { return }
        guard identityReviewViewModel.resolve(presentation.review.id, as: resolution) else { return }
        vaultDialogs.closeIdentityReview()
        let stableInitiating: Song?
        do {
            stableInitiating = try stableInitiatingSong(of: presentation)
        } catch {
            setProjectVaultStatusMessage(Self.identityChoiceSavedSettingsUnreadableMessage)
            return
        }
        guard let trigger = presentation.trigger, let current = stableInitiating else {
            setProjectVaultStatusMessage("Identity choice saved, but the project changed or is unavailable. Refresh and retry when the project is available. Nothing was archived.")
            return
        }
        switch trigger {
        case .workflowDone:
            requestWorkflowDoneReconfirmation(for: current)
        case .manual:
            requestArchiveNow(for: current)
        case .backupCopy:
            setProjectVaultStatusMessage("Identity resolved. Use Create Backup Copy to verify a Vault copy; the Active project stays in place.")
        @unknown default:
            return
        }
    }

    static let identityChoiceSavedSettingsUnreadableMessage =
        "Identity choice saved, but settings couldn't be read, so nothing was archived. Repair them in Settings, then try again."

    /// The initiating song of a current (triggered) review when it still
    /// resolves by stable location; nil for a persisted review or a failed
    /// resolution. Throws when settings cannot be read.
    private func stableInitiatingSong(of presentation: ProjectIdentityReviewPresentation) throws -> Song? {
        guard presentation.trigger != nil,
              let initiating = presentation.song,
              let current = songs.first(where: { $0.id == initiating.id }),
              try initiatingSongResolvesStably(current, for: presentation.review)
        else { return nil }
        return current
    }

    func cancelPresentedIdentityReview() {
        vaultDialogs.closeIdentityReview()
    }

    /// Stable title by catalog ProjectID only. Never falls back to a
    /// title-matched song: an unknown ID renders as "this project".
    private func titleForIdentityReview(_ review: ProjectIdentityReview) -> String {
        guard let store = projectCatalogStore,
              let entry = (try? store.loadEntries())?.first(where: {
                  $0.record.id == review.existingProjectID
              })
        else { return "this project" }
        return entry.record.canonicalTitle
    }

    /// Stable song by catalog (rootID, relativePath) location matching the
    /// review's ProjectIDs. Never matches by title or folder-name alone, so an
    /// unrelated same-title project is never bound. Returns the single matching
    /// song, or nil when there is no match or the match is ambiguous (failed
    /// resolution). Callers must not archive on nil.
    private func stableSongForIdentityReview(_ review: ProjectIdentityReview) -> Song? {
        // Display binding for a persisted review, which never archives.
        let matches = stableSongs(matching: review, musicRoots: appSettings.settings.musicRoots)
        guard matches.count == 1 else { return nil }
        return matches.first
    }

    /// The initiating song still earns fresh confirmation only when its current
    /// catalog path resolves to one of the review's stable ProjectIDs via
    /// location. Anything else (missing song, moved folder, unknown IDs, no
    /// locations) is a failed resolution and must not trigger a new archive.
    private func initiatingSongResolvesStably(_ song: Song, for review: ProjectIdentityReview) throws -> Bool {
        guard FileManager.default.fileExists(atPath: song.folderPath.path) else { return false }
        let roots = try library.loadSettingsForWrite().musicRoots
        return stableSongs(matching: review, musicRoots: roots).contains(where: { $0.id == song.id })
    }

    private func stableSongs(matching review: ProjectIdentityReview, musicRoots roots: [StoredMusicRoot]) -> [Song] {
        guard let store = projectCatalogStore,
              let entries = try? store.loadEntries()
        else { return [] }
        let wanted: Set<ProjectID> = [review.existingProjectID, review.candidateProjectID]
        let relevant = entries.filter { wanted.contains($0.record.id) }
        guard !relevant.isEmpty else { return [] }
        let activeLocations = relevant.flatMap { entry in
            entry.record.locations.filter { $0.kind == .active }
        }
        guard !activeLocations.isEmpty else { return [] }
        let bookmarkResolver = FoundationSecurityScopedBookmarks()
        func absoluteURL(for location: ProjectLocation) -> URL? {
            guard let root = roots.first(where: { $0.id == location.rootID }),
                  let resolved = try? root.resolvedURL(using: bookmarkResolver),
                  !location.relativePath.isEmpty,
                  !location.relativePath.hasPrefix("/")
            else { return nil }
            return resolved.appendingPathComponent(location.relativePath)
        }
        let locationPaths = Set(activeLocations.compactMap { location in
            absoluteURL(for: location).map(Self.vaultCanonicalPath)
        })
        guard !locationPaths.isEmpty else { return [] }
        return songs.filter { song in
            locationPaths.contains(Self.vaultCanonicalPath(song.folderPath))
        }
    }
}
