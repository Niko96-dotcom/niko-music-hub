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

    private var estimator: TempoEstimator
    private let historyStore: any BPMHistoryStore
    private let clipboard: any BPMClipboardWriting

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
        rawBPM = nil
        tapCount = 0
        statusText = "Tap the pad or press Space"
        statusKind = .idle
        hasStartedRun = false
    }

    public func recordTap(at timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        let estimate = estimator.tap(at: timestamp)
        rawBPM = estimate.bpm
        tapCount = estimate.tapCount
        hasStartedRun = true
        clearTransientMessages()
        applyStatus(from: estimate.status)
    }

    public func resetTaps() {
        estimator.reset()
        rawBPM = nil
        tapCount = 0
        statusText = "Tap the pad or press Space"
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
        errorText = nil
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
        } catch {
            errorText = "Could not save this BPM. Check local app storage, then try Save BPM again."
            saveConfirmation = nil
        }
    }

    public func copySavedBPM(_ entry: BPMHistoryEntry) {
        clipboard.copyPlainNumber(formatBPM(entry.bpm))
        copyConfirmation = "BPM copied"
        saveConfirmation = nil
        errorText = nil
    }

    public func loadHistory() throws {
        historyEntries = try historyStore.listEntries()
    }

    public func clearHistory() {
        do {
            try historyStore.clearEntries()
            try loadHistory()
            copyConfirmation = nil
            saveConfirmation = nil
            errorText = nil
        } catch {
            errorText = "Could not save this BPM. Check local app storage, then try Save BPM again."
        }
    }

    private func applyStatus(from status: TempoEstimatorStatus) {
        switch status {
        case .idle:
            statusText = "Tap the pad or press Space"
            statusKind = .idle
        case .waitingForSecondTap:
            statusText = "Tap the pad or press Space"
            statusKind = .waitingForSecondTap
        case .firstEstimate:
            statusText = "First estimate ready. Keep tapping to steady it."
            statusKind = .firstEstimate
        case .stableEstimate:
            statusText = "Stable average from recent taps."
            statusKind = .stableEstimate
        case .longPauseReset:
            statusText = "New tap run started."
            statusKind = .longPauseReset
        case .outlierIgnored:
            statusText = "Ignored one uneven tap. Keep tapping."
            statusKind = .outlierIgnored
        }
    }

    private func clearTransientMessages() {
        copyConfirmation = nil
        saveConfirmation = nil
        errorText = nil
    }

    private func formatBPM(_ bpm: Double) -> String {
        String(Int(bpm.rounded()))
    }
}
