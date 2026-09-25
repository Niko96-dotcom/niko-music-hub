import Foundation

public enum BPMTapperStatusKind: Equatable, Sendable {
    case idle
    case waitingForSecondTap
    case firstEstimate
    case stableEstimate
    case longPauseReset
    case outlierIgnored
}

@MainActor
public final class BPMTapperViewModel: ObservableObject {
    @Published public private(set) var rawBPM: Double?
    @Published public private(set) var tapCount: Int
    @Published public private(set) var statusText: String
    @Published public private(set) var statusKind: BPMTapperStatusKind
    @Published public private(set) var hasStartedRun: Bool
    @Published public private(set) var adjustment: BPMAdjustment = .original
    @Published public private(set) var historyEntries: [BPMHistoryEntry] = []
    @Published public private(set) var copyConfirmation: String?
    @Published public private(set) var saveConfirmation: String?
    @Published public private(set) var errorText: String?
    /// B1: true while the persisted history is unreadable. Keeps Clear
    /// History enabled so the user can discard the bad payload.
    @Published public private(set) var hasCorruptHistory = false

    /// Shown when the persisted history cannot be decoded. Points at both
    /// recovery paths; the live slot already renders `errorText`.
    public static let corruptHistoryMessage =
        "Saved BPM history was unreadable. Clear History or Save BPM starts fresh; a backup is kept."
    private static let saveFailureMessage =
        "Could not save this BPM. Check local app storage, then try Save BPM again."

    private var estimator: TempoEstimator
    private let historyStore: any BPMHistoryStore
    private let clipboard: any BPMClipboardWriting
    // Sleep-inclusive monotonic source for default taps. ContinuousClock keeps
    // advancing across sleep (unlike ProcessInfo.systemUptime, which only
    // counts awake time) while staying monotonic across wall-clock steps, so a
    // lid-close longer than the pause threshold starts a fresh run.
    private var monotonicNow: () -> TimeInterval

    public var displayedBPM: Double? {
        guard let rawBPM else { return nil }
        return adjustment.apply(to: rawBPM)
    }

    public init(
        estimator: TempoEstimator = TempoEstimator(),
        historyStore: any BPMHistoryStore = UserDefaultsBPMHistoryStore(),
        clipboard: any BPMClipboardWriting = NoOpBPMClipboard()
    ) {
        self.estimator = estimator
        self.historyStore = historyStore
        self.clipboard = clipboard
        monotonicNow = { Self.sleepInclusiveNow() }
        rawBPM = nil
        tapCount = 0
        statusText = ""
        statusKind = .idle
        hasStartedRun = false
    }

    /// Sleep-inclusive monotonic now, in seconds on an arbitrary process-local
    /// epoch. Differences match elapsed wall time including sleep, which is
    /// what the pause-reset threshold must observe.
    nonisolated internal static func sleepInclusiveNow() -> TimeInterval {
        let duration = continuousEpoch.duration(to: ContinuousClock().now)
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000.0
    }

    private nonisolated static let continuousEpoch: ContinuousClock.Instant = ContinuousClock().now

    /// Deterministic seam for tests: proves pause semantics of the default
    /// `recordTap()` path without sleeping the host or stepping the clock.
    internal func setMonotonicNowForTesting(_ provider: @escaping () -> TimeInterval) {
        monotonicNow = provider
    }

    /// Default tap path: uses the sleep-inclusive monotonic clock so a sleep
    /// longer than the pause threshold starts a fresh run.
    public func recordTap() {
        recordTap(at: monotonicNow())
    }

    public func recordTap(at timestamp: TimeInterval) {
        let estimate = estimator.tap(at: timestamp)
        applyTapEstimate(estimate)
    }

    private func applyTapEstimate(_ estimate: TempoEstimate) {
        rawBPM = estimate.bpm
        tapCount = estimate.tapCount
        // Ignored (invalid/non-forward) taps never start a run on their own.
        if estimate.tapCount > 0 {
            hasStartedRun = true
        }
        clearTransientMessages()
        applyStatus(from: estimate.status)
    }

    public func resetTaps() {
        estimator.reset()
        rawBPM = nil
        tapCount = 0
        statusText = ""
        statusKind = .idle
        hasStartedRun = false
        clearTransientMessages()
    }

    public func setAdjustment(_ adjustment: BPMAdjustment) {
        self.adjustment = adjustment
        clearTransientMessages()
    }

    public func copyDisplayedBPM() {
        guard let displayedBPM else { return }
        clipboard.copyPlainNumber(formatBPM(displayedBPM))
        copyConfirmation = "BPM copied"
        saveConfirmation = nil
        if !hasCorruptHistory {
            errorText = nil
        }
    }

    public func saveDisplayedBPM() {
        guard let displayedBPM, let rawBPM else { return }
        let entry = BPMHistoryEntry(
            bpm: displayedBPM,
            rawTappedBPM: rawBPM,
            adjustment: adjustment,
            timestamp: Date()
        )

        do {
            try historyStore.addEntry(entry)
            try loadHistory()
            saveConfirmation = "BPM saved"
            copyConfirmation = nil
            errorText = nil
        } catch is DecodingError {
            // A store without B1 quarantine still throws here; surface the
            // corrupt-history copy so Clear/Save stay discoverable.
            hasCorruptHistory = true
            errorText = Self.corruptHistoryMessage
            saveConfirmation = nil
        } catch {
            errorText = Self.saveFailureMessage
            saveConfirmation = nil
        }
    }

    public func copySavedBPM(_ entry: BPMHistoryEntry) {
        clipboard.copyPlainNumber(formatBPM(entry.bpm))
        copyConfirmation = "BPM copied"
        saveConfirmation = nil
        if !hasCorruptHistory {
            errorText = nil
        }
    }

    public func loadHistory() throws {
        do {
            historyEntries = try historyStore.listEntries()
            hasCorruptHistory = false
        } catch let error as DecodingError {
            // B1: keep the decode failure visible (the view's `try?` in
            // onAppear would otherwise swallow it into an empty list with
            // Clear disabled and Save failing forever).
            historyEntries = []
            hasCorruptHistory = true
            errorText = Self.corruptHistoryMessage
            throw error
        }
    }

    public func clearHistory() {
        do {
            // clearEntries is decode-free, so this recovers from corruption.
            // The current tap run (estimator, rawBPM, tapCount) is untouched.
            try historyStore.clearEntries()
            try loadHistory()
            copyConfirmation = nil
            saveConfirmation = nil
            errorText = nil
            hasCorruptHistory = false
        } catch is DecodingError {
            hasCorruptHistory = true
            if errorText == nil {
                errorText = Self.corruptHistoryMessage
            }
        } catch BPMHistoryStoreError.corruptBackupFailed {
            // The live malformed bytes were left in place, so keep the
            // truthful corrupt-history copy visible for a later Clear/Save.
            hasCorruptHistory = true
            errorText = Self.corruptHistoryMessage
        } catch {
            // A failed Clear after corruption must not replace the truthful
            // corrupt copy with a generic save failure.
            if hasCorruptHistory {
                errorText = Self.corruptHistoryMessage
            } else {
                errorText = Self.saveFailureMessage
            }
        }
    }

    /// NMH-043: the BPM error card's Try Again action retries the failed
    /// storage work (reload history, then re-attempt the pending save).
    public func retryAfterStorageError() {
        do {
            try loadHistory()
            if displayedBPM != nil {
                saveDisplayedBPM()
            } else {
                errorText = nil
            }
        } catch is DecodingError {
            // loadHistory already published the corrupt-history copy.
            hasCorruptHistory = true
        } catch {
            errorText = Self.saveFailureMessage
        }
    }

    private func applyStatus(from status: TempoEstimatorStatus) {
        switch status {
        // Idle/stable carry no fact the readout does not already show (empty
        // status hides the header line); only transitions earn a line.
        case .idle:
            statusText = ""
            statusKind = .idle
        case .waitingForSecondTap:
            statusText = ""
            statusKind = .waitingForSecondTap
        case .firstEstimate:
            statusText = "First estimate — keep tapping"
            statusKind = .firstEstimate
        case .stableEstimate:
            statusText = ""
            statusKind = .stableEstimate
        case .longPauseReset:
            statusText = "New tap run started"
            statusKind = .longPauseReset
        case .outlierIgnored:
            statusText = "Uneven tap ignored"
            statusKind = .outlierIgnored
        }
    }

    private func clearTransientMessages() {
        copyConfirmation = nil
        saveConfirmation = nil
        // Corrupt-history copy stays visible across taps, resets, copies, and
        // adjustment changes until Clear History or a successful Save repairs
        // storage; only non-corruption messages clear here.
        if !hasCorruptHistory {
            errorText = nil
        }
    }

    private func formatBPM(_ bpm: Double) -> String {
        String(Int(bpm.rounded()))
    }
}
