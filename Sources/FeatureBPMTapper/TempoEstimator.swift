import Foundation

public struct TempoEstimatorConfiguration: Equatable, Sendable {
    public enum Defaults {
        public static let recentIntervalLimit = 12
        public static let stableIntervalThreshold = 4
        public static let pauseResetThreshold = 2.5
    }

    public var recentIntervalLimit: Int
    public var stableIntervalThreshold: Int
    public var pauseResetThreshold: TimeInterval
    public var minimumInterval: TimeInterval
    public var maximumInterval: TimeInterval
    /// How far a tap may land from the next beat on the fitted grid, in beats,
    /// and how much two intervals may differ (as a fraction of the earlier one)
    /// and still count as the same new spacing.
    public var outlierTolerance: Double

    public init(
        recentIntervalLimit: Int = Defaults.recentIntervalLimit,
        stableIntervalThreshold: Int = Defaults.stableIntervalThreshold,
        pauseResetThreshold: TimeInterval = Defaults.pauseResetThreshold,
        minimumInterval: TimeInterval = 0.24,
        maximumInterval: TimeInterval = 2.0,
        outlierTolerance: Double = 0.50
    ) {
        self.recentIntervalLimit = max(1, recentIntervalLimit)
        self.stableIntervalThreshold = max(1, stableIntervalThreshold)
        self.pauseResetThreshold = pauseResetThreshold
        self.minimumInterval = minimumInterval
        self.maximumInterval = maximumInterval
        self.outlierTolerance = outlierTolerance
    }
}

public enum TempoEstimatorStatus: Equatable, Sendable {
    case idle
    case waitingForSecondTap
    case firstEstimate
    case stableEstimate
    case longPauseReset
    case outlierIgnored
}

public struct TempoEstimate: Equatable, Sendable {
    public let bpm: Double?
    public let tapCount: Int
    public let acceptedIntervalCount: Int
    public let status: TempoEstimatorStatus
    public let intervalAccepted: Bool

    public init(
        bpm: Double?,
        tapCount: Int,
        acceptedIntervalCount: Int,
        status: TempoEstimatorStatus,
        intervalAccepted: Bool
    ) {
        self.bpm = bpm
        self.tapCount = tapCount
        self.acceptedIntervalCount = acceptedIntervalCount
        self.status = status
        self.intervalAccepted = intervalAccepted
    }
}

/// Reads the tempo of a tap run from the slope of a least-squares line of tap
/// time over beat number.
///
/// A person tapping along to a song lands early or late around the song's
/// fixed beat grid, and those errors do not add up. Averaging the intervals
/// between taps keeps every tap's jitter in the result; the slope of tap time
/// against beat number cancels it. For twelve intervals of ordinary human
/// jitter the slope lands three to four times closer to the song's tempo than
/// the median interval does (`docs/bpm-tapper-algorithm.md`).
///
/// Every accepted tap carries a whole beat number. A tap within half a beat of
/// the next grid beat is that beat. A tap on a later grid beat, within a
/// quarter beat, is a missed beat and counts the beats it skipped. Any other
/// tap is ignored. Three taps in a row at one spacing that does not fit the grid
/// are a new tempo and start a new run from those taps.
public struct TempoEstimator: Sendable {
    public let configuration: TempoEstimatorConfiguration

    private struct BeatTap: Sendable {
        let beat: Int
        let timestamp: TimeInterval
    }

    /// The fitted line: `origin` is the time of beat 0, `period` the beat length.
    private struct BeatGrid {
        let period: TimeInterval
        let origin: TimeInterval

        func beat(at timestamp: TimeInterval) -> Double {
            (timestamp - origin) / period
        }
    }

    private struct OffGridInterval: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        var length: TimeInterval { end - start }
    }

    /// Last tap of the run, accepted or ignored. The pause rule and the
    /// tempo-change rule measure from here, so one stray tap does not make
    /// every following interval look long.
    private var anchorTimestamp: TimeInterval?
    /// The window the grid is fitted to: the run's start tap, then at most
    /// `recentIntervalLimit` more accepted taps.
    private var acceptedTaps: [BeatTap]
    private var acceptedTapCount: Int
    private var currentBPM: Double?
    /// Consecutive taps that did not fit the grid as the next beat and share one
    /// spacing. The third such tap starts a new run at that spacing.
    private var offGridIntervals: [OffGridInterval]

    /// A missed beat must land this close to a later grid beat, in beats. The
    /// band is tighter than for the next beat because a wrong beat number costs
    /// far more than one ignored tap.
    private static let missedBeatTolerance = 0.25
    private static let tempoChangeIntervalCount = 3

    public init(configuration: TempoEstimatorConfiguration = TempoEstimatorConfiguration()) {
        self.configuration = configuration
        anchorTimestamp = nil
        acceptedTaps = []
        offGridIntervals = []
        acceptedTapCount = 0
        currentBPM = nil
    }

    public mutating func tap(at timestamp: TimeInterval) -> TempoEstimate {
        // Non-finite wall-clock glitches must never poison the anchor.
        guard timestamp.isFinite else {
            guard anchorTimestamp != nil else {
                return makeEstimate(status: .idle, intervalAccepted: false)
            }
            return makeEstimate(status: .outlierIgnored, intervalAccepted: false)
        }
        guard let previousTimestamp = anchorTimestamp else {
            startRun(at: timestamp)
            return makeEstimate(status: .waitingForSecondTap, intervalAccepted: true)
        }

        // Zero/backward timestamps are not forward progress: ignore them
        // without rewinding the anchor or touching count/tempo.
        guard timestamp > previousTimestamp else {
            return makeEstimate(status: .outlierIgnored, intervalAccepted: false)
        }

        let interval = timestamp - previousTimestamp
        guard interval.isFinite else {
            return makeEstimate(status: .outlierIgnored, intervalAccepted: false)
        }
        guard interval <= configuration.pauseResetThreshold else {
            startRun(at: timestamp)
            return makeEstimate(status: .longPauseReset, intervalAccepted: true)
        }

        anchorTimestamp = timestamp
        guard interval >= configuration.minimumInterval, interval <= configuration.maximumInterval else {
            offGridIntervals = []
            return makeEstimate(status: .outlierIgnored, intervalAccepted: false)
        }

        // Two intervals define the first grid; until then every spaced tap is a beat.
        guard acceptedTaps.count >= 3 else {
            return accept(beats: 1, at: timestamp)
        }

        let lastBeat = acceptedTaps[acceptedTaps.count - 1].beat
        let beatsSinceLastTap = fittedGrid().beat(at: timestamp) - Double(lastBeat)
        if abs(beatsSinceLastTap - 1) < configuration.outlierTolerance {
            offGridIntervals = []
            return accept(beats: 1, at: timestamp)
        }

        // Not the next beat. The same new spacing three taps in a row is a tempo
        // change: start over from those taps instead of keeping a stale grid.
        if let last = offGridIntervals.last, !matchesSpacing(interval, last.length) {
            offGridIntervals = []
        }
        offGridIntervals.append(OffGridInterval(start: previousTimestamp, end: timestamp))
        if offGridIntervals.count >= Self.tempoChangeIntervalCount {
            startRun(seededWith: [offGridIntervals[0].start] + offGridIntervals.map(\.end))
            return makeEstimate(status: .longPauseReset, intervalAccepted: true)
        }

        // A tap on a later grid beat is a missed beat: it counts the beats it
        // skipped. Anything else is a stray tap.
        let wholeBeats = beatsSinceLastTap.rounded()
        if wholeBeats >= 2, abs(beatsSinceLastTap - wholeBeats) < Self.missedBeatTolerance {
            return accept(beats: Int(wholeBeats), at: timestamp)
        }
        return makeEstimate(status: .outlierIgnored, intervalAccepted: false)
    }

    public mutating func reset() {
        anchorTimestamp = nil
        acceptedTaps = []
        offGridIntervals = []
        acceptedTapCount = 0
        currentBPM = nil
    }

    private mutating func startRun(at timestamp: TimeInterval) {
        anchorTimestamp = timestamp
        acceptedTaps = [BeatTap(beat: 0, timestamp: timestamp)]
        offGridIntervals = []
        acceptedTapCount = 1
        currentBPM = nil
    }

    /// Starts a run whose taps are already known to be one beat apart.
    private mutating func startRun(seededWith timestamps: [TimeInterval]) {
        anchorTimestamp = timestamps[timestamps.count - 1]
        acceptedTaps = timestamps.enumerated().map { BeatTap(beat: $0.offset, timestamp: $0.element) }
        offGridIntervals = []
        acceptedTapCount = timestamps.count
        currentBPM = bpm(from: fittedGrid())
    }

    private mutating func accept(beats: Int, at timestamp: TimeInterval) -> TempoEstimate {
        let beat = acceptedTaps[acceptedTaps.count - 1].beat + beats
        acceptedTaps.append(BeatTap(beat: beat, timestamp: timestamp))
        let tapLimit = configuration.recentIntervalLimit + 1
        if acceptedTaps.count > tapLimit {
            acceptedTaps.removeFirst(acceptedTaps.count - tapLimit)
        }
        acceptedTapCount += 1
        currentBPM = bpm(from: fittedGrid())

        let stableThreshold = min(configuration.stableIntervalThreshold, configuration.recentIntervalLimit)
        let status: TempoEstimatorStatus = acceptedTaps.count - 1 >= stableThreshold
            ? .stableEstimate
            : .firstEstimate
        return makeEstimate(status: status, intervalAccepted: true)
    }

    private func matchesSpacing(_ interval: TimeInterval, _ reference: TimeInterval) -> Bool {
        abs(interval - reference) <= reference * configuration.outlierTolerance
    }

    /// Least-squares line of tap time over beat number. Needs two taps; beat
    /// numbers strictly increase, so the variance is never zero.
    private func fittedGrid() -> BeatGrid {
        let count = Double(acceptedTaps.count)
        let meanBeat = acceptedTaps.reduce(0.0) { $0 + Double($1.beat) } / count
        let meanTime = acceptedTaps.reduce(0.0) { $0 + $1.timestamp } / count
        var covariance = 0.0
        var variance = 0.0
        for tap in acceptedTaps {
            let beatOffset = Double(tap.beat) - meanBeat
            covariance += beatOffset * (tap.timestamp - meanTime)
            variance += beatOffset * beatOffset
        }
        let period = covariance / variance
        return BeatGrid(period: period, origin: meanTime - period * meanBeat)
    }

    private func bpm(from grid: BeatGrid) -> Double? {
        guard grid.period.isFinite, grid.period > 0 else { return nil }
        return 60.0 / grid.period
    }

    private func makeEstimate(
        status: TempoEstimatorStatus,
        intervalAccepted: Bool
    ) -> TempoEstimate {
        TempoEstimate(
            bpm: currentBPM,
            tapCount: acceptedTapCount,
            acceptedIntervalCount: max(0, acceptedTaps.count - 1),
            status: status,
            intervalAccepted: intervalAccepted
        )
    }
}
