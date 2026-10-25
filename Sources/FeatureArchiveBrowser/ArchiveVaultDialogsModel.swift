import AppCore
import Combine
import Foundation
import NikoMusicCore
import ProjectVaultRuntime

/// The Project Vault dialogs the archive page presents, and the bound-authorization
/// capture that comes before the archive dialog: the archive/Done confirmation,
/// the restore sheet and the progress of a running restore, the identity review,
/// the stop-transfer alert, and whether quit has stopped the Vault.
///
/// Rules it owns:
///
/// - Every explicit archive confirmation captures its authorization before the
///   dialog shows. Each capture gets a new generation; only the capture of the
///   current generation may present its dialog, so a superseded or cancelled
///   capture never produces a late modal (`beginCapture`, `isCurrentCapture`).
/// - Cancelling one song's capture never drops another song's dialog or capture
///   (`cancelCapture(for:)`).
/// - A restore sheet opens only while no restore sheet is open and no restore
///   options are loading.
/// - Once quit has stopped the Vault (ADR-019) it stays stopped for this run.
///
/// The view model runs the captures, the runtime calls and the queue; this model
/// holds what they present. `ArchiveBrowserViewModel` forwards its publishes.
@MainActor
final class ArchiveVaultDialogsModel: ObservableObject {
    // MARK: - Archive confirmation and its capture

    @Published private(set) var pendingArchiveConfirmation: ProjectVaultArchiveConfirmation?
    /// The song whose authorization is being captured, nil when no capture runs.
    private(set) var captureSongID: String?
    /// Bumped by every capture start and cancel; only the current one may present.
    private(set) var captureGeneration: UInt64 = 0
    private var captureTask: Task<Void, Never>?
    /// Deterministic seam for behavioral tests: awaited at the start of every
    /// bound-authorization capture so settings/roots/source changes can be
    /// applied while a confirmation is still in flight.
    var captureProbe: (@Sendable () async -> Void)?

    // MARK: - Other dialogs

    @Published private(set) var projectVaultRestoreRequest: ProjectVaultRestoreRequest?
    @Published private(set) var projectVaultRestoreProgress: ProjectVaultRestoreProgress?
    private(set) var restoreOptionsLoading = false
    @Published private(set) var identityReviewPresentation: ProjectIdentityReviewPresentation?
    @Published private(set) var pendingStopTransferConfirmation = false
    /// Set once quit has stopped the Vault queue (ADR-019): no new operation is
    /// queued and no recovery is scheduled for the exiting app to cut off.
    private(set) var stoppedForQuit = false

    init() {}

    /// `Task.cancel()` is thread-safe, so `deinit` cancels the capture directly.
    deinit {
        captureTask?.cancel()
    }

    /// A Vault dialog that `ArchiveBrowserView` presents is waiting. SwiftUI
    /// shows it only once no other sheet is open, so the song detail closes
    /// "Manage storage" for it instead of hiding it until the user does.
    var hasPendingDialog: Bool {
        pendingArchiveConfirmation != nil
            || projectVaultRestoreRequest != nil
            || identityReviewPresentation != nil
            || pendingStopTransferConfirmation
    }

    // MARK: - Capture

    /// Starts a capture for `songID`: `makeTask` gets the capture's generation and
    /// returns the task that runs it. A new capture supersedes the previous one
    /// and the dialog it presented.
    func beginCapture(songID: String, task makeTask: (UInt64) -> Task<Void, Never>) {
        captureGeneration &+= 1
        let generation = captureGeneration
        captureTask?.cancel()
        // A replacement supersedes any presented dialog for the previous
        // capture; the new capture re-presents only when it is still current.
        pendingArchiveConfirmation = nil
        captureSongID = songID
        captureTask = makeTask(generation)
    }

    func isCurrentCapture(_ generation: UInt64) -> Bool {
        captureGeneration == generation
    }

    /// The capture for `songID` ended without a dialog.
    func endCapture(songID: String) {
        if captureSongID == songID {
            captureSongID = nil
        }
    }

    /// The capture of `generation` for `songID` ended without a dialog, if it is
    /// still the current one.
    func endCurrentCapture(songID: String, generation: UInt64) {
        if isCurrentCapture(generation), captureSongID == songID {
            captureSongID = nil
        }
    }

    /// The capture of `generation` presents its dialog, if it is still current.
    func presentConfirmation(_ confirmation: ProjectVaultArchiveConfirmation, generation: UInt64) {
        guard isCurrentCapture(generation) else { return }
        endCapture(songID: confirmation.songID)
        pendingArchiveConfirmation = confirmation
    }

    /// Cancels an in-flight capture for one song (or every capture when `songID`
    /// is nil). Per-song ownership: cancelling one song never drops a different
    /// song's dialog or capture. Bumping the generation guarantees a superseded
    /// capture can never present a stale late modal after its awaits.
    func cancelCapture(for songID: String? = nil) {
        if let songID {
            if let pendingSong = pendingArchiveConfirmation?.songID,
               pendingSong != songID,
               captureSongID != songID {
                return
            }
            if let capturing = captureSongID, capturing != songID {
                return
            }
            let ownsDialog = pendingArchiveConfirmation?.songID == songID
            let ownsCapture = captureSongID == songID
            if !ownsDialog && !ownsCapture {
                return
            }
            captureGeneration &+= 1
            captureTask?.cancel()
            captureTask = nil
            if captureSongID == songID {
                captureSongID = nil
            }
            if pendingArchiveConfirmation?.songID == songID {
                pendingArchiveConfirmation = nil
            }
            return
        }
        captureGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        captureSongID = nil
        pendingArchiveConfirmation = nil
    }

    /// The person answered the dialog: it closes and the capture is over.
    func closeConfirmation() {
        pendingArchiveConfirmation = nil
        captureTask = nil
        captureSongID = nil
    }

    /// The dialog of this song closes (an undo or a cancelled queue entry);
    /// another song's dialog stays.
    func dismissConfirmation(for songID: String) {
        if pendingArchiveConfirmation?.songID == songID {
            pendingArchiveConfirmation = nil
        }
    }

    /// Every pending archive dialog closes (the queue was cancelled).
    func dismissConfirmation() {
        pendingArchiveConfirmation = nil
    }

    // MARK: - Restore

    /// Starts loading restore options. False while a restore sheet is open or
    /// options are already loading.
    func beginRestoreOptionsLoad() -> Bool {
        guard projectVaultRestoreRequest == nil, !restoreOptionsLoading else { return false }
        restoreOptionsLoading = true
        return true
    }

    func endRestoreOptionsLoad() {
        restoreOptionsLoading = false
    }

    func presentRestore(_ request: ProjectVaultRestoreRequest) {
        projectVaultRestoreRequest = request
    }

    func closeRestore() {
        projectVaultRestoreRequest = nil
    }

    /// The running restore's progress; publishes only a change.
    func updateRestoreProgress(_ progress: ProjectVaultRestoreProgress?) {
        if projectVaultRestoreProgress != progress {
            projectVaultRestoreProgress = progress
        }
    }

    /// The operation that tracked restore progress ended.
    func clearRestoreProgress() {
        projectVaultRestoreProgress = nil
    }

    // MARK: - Identity review

    func presentIdentityReview(_ presentation: ProjectIdentityReviewPresentation) {
        identityReviewPresentation = presentation
    }

    func closeIdentityReview() {
        identityReviewPresentation = nil
    }

    // MARK: - Stop transfer and quit

    func askToStopTransfer() {
        pendingStopTransferConfirmation = true
    }

    func closeStopTransferQuestion() {
        pendingStopTransferConfirmation = false
    }

    func markStoppedForQuit() {
        stoppedForQuit = true
    }
}
