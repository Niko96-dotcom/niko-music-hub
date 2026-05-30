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

public struct TempoEstimator: Sendable {
    public let configuration: TempoEstimatorConfiguration

    private var lastAcceptedTimestamp: TimeInterval?
    private var acceptedIntervals: [TimeInterval]
    private var acceptedTapCount: Int
    private var currentBPM: Double?

    public init(configuration: TempoEstimatorConfiguration = TempoEstimatorConfiguration()) {
        self.configuration = configuration
        lastAcceptedTimestamp = nil
        acceptedIntervals = []
        acceptedTapCount = 0
        currentBPM = nil
    }

    public mutating func tap(at timestamp: TimeInterval) -> TempoEstimate {
        guard let previousTimestamp = lastAcceptedTimestamp else {
            startRun(at: timestamp)
            return makeEstimate(status: .waitingForSecondTap, intervalAccepted: true)
        }

        let interval = timestamp - previousTimestamp
        guard interval <= configuration.pauseResetThreshold else {
            startRun(at: timestamp)
            return makeEstimate(status: .longPauseReset, intervalAccepted: true)
        }

        guard isIntervalAccepted(interval) else {
            // Let the next tap recover from one uneven tap instead of comparing
            // every following interval against an increasingly stale timestamp.
            lastAcceptedTimestamp = timestamp
            return makeEstimate(status: .outlierIgnored, intervalAccepted: false)
        }

        acceptedIntervals.append(interval)
        if acceptedIntervals.count > configuration.recentIntervalLimit {
            acceptedIntervals.removeFirst(acceptedIntervals.count - configuration.recentIntervalLimit)
        }

        lastAcceptedTimestamp = timestamp
        acceptedTapCount += 1
        currentBPM = bpm(from: acceptedIntervals)

        let stableThreshold = min(configuration.stableIntervalThreshold, configuration.recentIntervalLimit)
        let status: TempoEstimatorStatus = acceptedIntervals.count >= stableThreshold
            ? .stableEstimate
            : .firstEstimate
        return makeEstimate(status: status, intervalAccepted: true)
    }

    public mutating func reset() {
        lastAcceptedTimestamp = nil
        acceptedIntervals = []
        acceptedTapCount = 0
        currentBPM = nil
    }

    private mutating func startRun(at timestamp: TimeInterval) {
        lastAcceptedTimestamp = timestamp
        acceptedIntervals = []
        acceptedTapCount = 1
        currentBPM = nil
    }

    private func isIntervalAccepted(_ interval: TimeInterval) -> Bool {
        guard interval >= configuration.minimumInterval,
              interval <= configuration.maximumInterval else {
            return false
        }

        guard acceptedIntervals.count >= 2 else {
            return true
        }

        let baseline = robustCentralInterval(acceptedIntervals)
        if matchesBaseline(interval, baseline) {
            return true
        }
        // Short “double-tap” between beats: count as one beat when it is clearly half the baseline.
        if interval < baseline * 0.6, matchesBaseline(interval * 2.0, baseline) {
            return true
        }
        return false
    }

    private func matchesBaseline(_ interval: TimeInterval, _ baseline: TimeInterval) -> Bool {
        guard baseline > 0 else { return true }
        let lowerBound = baseline * (1.0 - configuration.outlierTolerance)
        let upperBound = baseline * (1.0 + configuration.outlierTolerance)
        return interval >= lowerBound && interval <= upperBound
    }

    private func bpm(from intervals: [TimeInterval]) -> Double? {
        let centralInterval = robustCentralInterval(intervals)
        guard centralInterval > 0 else { return nil }
        return 60.0 / centralInterval
    }

    /// Median resists occasional bad taps; mean is fine for the first two intervals.
    private func robustCentralInterval(_ intervals: [TimeInterval]) -> TimeInterval {
        guard intervals.count >= 3 else {
            return average(intervals)
        }
        return median(intervals)
    }

    private func average(_ intervals: [TimeInterval]) -> TimeInterval {
        guard !intervals.isEmpty else { return 0 }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    private func median(_ intervals: [TimeInterval]) -> TimeInterval {
        let sorted = intervals.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
    }

    private func makeEstimate(
        status: TempoEstimatorStatus,
        intervalAccepted: Bool
    ) -> TempoEstimate {
        TempoEstimate(
            bpm: currentBPM,
            tapCount: acceptedTapCount,
            acceptedIntervalCount: acceptedIntervals.count,
            status: status,
            intervalAccepted: intervalAccepted
        )
    }
}
