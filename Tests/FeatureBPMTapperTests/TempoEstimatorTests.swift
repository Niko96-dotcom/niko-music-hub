import FeatureBPMTapper
import XCTest

final class TempoEstimatorTests: XCTestCase {
    func testFirstTapWaitsForSecondTap() {
        var estimator = TempoEstimator()

        let estimate = estimator.tap(at: 10.0)

        XCTAssertNil(estimate.bpm)
        XCTAssertEqual(estimate.tapCount, 1)
        XCTAssertEqual(estimate.acceptedIntervalCount, 0)
        XCTAssertEqual(estimate.status, .waitingForSecondTap)
        XCTAssertTrue(estimate.intervalAccepted)
    }

    func testSecondTapProducesFirstEstimate() throws {
        var estimator = TempoEstimator()
        _ = estimator.tap(at: 0.0)

        let estimate = estimator.tap(at: 0.5)

        XCTAssertEqual(try XCTUnwrap(estimate.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(estimate.tapCount, 2)
        XCTAssertEqual(estimate.acceptedIntervalCount, 1)
        XCTAssertEqual(estimate.status, .firstEstimate)
    }

    func testUsesLongerRollingAverageByDefault() throws {
        var estimator = TempoEstimator()
        let intervals: [TimeInterval] = [0.50, 0.50, 0.50, 0.50, 0.60, 0.60, 0.60, 0.60]

        var estimate: TempoEstimate?
        var timestamp: TimeInterval = 0.0
        estimate = estimator.tap(at: timestamp)
        for interval in intervals {
            timestamp += interval
            estimate = estimator.tap(at: timestamp)
        }

        let finalEstimate = try XCTUnwrap(estimate)
        let expectedBPM = 60.0 / (intervals.reduce(0, +) / Double(intervals.count))
        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), expectedBPM, accuracy: 0.001)
        XCTAssertEqual(finalEstimate.acceptedIntervalCount, 8)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testRollingAverageDropsOnlyAfterConfiguredLimit() throws {
        let configuration = TempoEstimatorConfiguration(recentIntervalLimit: 3)
        var estimator = TempoEstimator(configuration: configuration)
        let intervals: [TimeInterval] = [0.50, 0.50, 0.60, 0.60]

        var estimate: TempoEstimate?
        var timestamp: TimeInterval = 0.0
        estimate = estimator.tap(at: timestamp)
        for interval in intervals {
            timestamp += interval
            estimate = estimator.tap(at: timestamp)
        }

        let finalEstimate = try XCTUnwrap(estimate)
        let expectedBPM = 60.0 / 0.60
        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), expectedBPM, accuracy: 0.001)
        XCTAssertEqual(finalEstimate.acceptedIntervalCount, 3)
    }

    func testLongPauseStartsFreshRun() {
        var estimator = TempoEstimator()
        _ = estimator.tap(at: 0.0)
        _ = estimator.tap(at: 0.5)

        let estimate = estimator.tap(at: 3.5)

        XCTAssertNil(estimate.bpm)
        XCTAssertEqual(estimate.tapCount, 1)
        XCTAssertEqual(estimate.acceptedIntervalCount, 0)
        XCTAssertEqual(estimate.status, .longPauseReset)
        XCTAssertTrue(estimate.intervalAccepted)
    }

    func testIgnoresObviousOutlier() throws {
        var estimator = TempoEstimator()
        _ = estimator.tap(at: 0.0)
        _ = estimator.tap(at: 0.5)
        _ = estimator.tap(at: 1.0)

        let stableEstimate = estimator.tap(at: 1.5)
        let outlierEstimate = estimator.tap(at: 1.58)

        XCTAssertEqual(try XCTUnwrap(stableEstimate.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(outlierEstimate.bpm, stableEstimate.bpm)
        XCTAssertEqual(outlierEstimate.tapCount, stableEstimate.tapCount)
        XCTAssertEqual(outlierEstimate.acceptedIntervalCount, stableEstimate.acceptedIntervalCount)
        XCTAssertEqual(outlierEstimate.status, .outlierIgnored)
        XCTAssertFalse(outlierEstimate.intervalAccepted)
    }

    func testSimulated120BPMWithHumanJitter() throws {
        var estimator = TempoEstimator()
        let jitteredIntervals: [TimeInterval] = [
            0.48, 0.52, 0.49, 0.51, 0.50, 0.50, 0.47, 0.53, 0.50, 0.50, 0.51, 0.49,
        ]

        var estimate: TempoEstimate?
        var timestamp: TimeInterval = 0.0
        estimate = estimator.tap(at: timestamp)
        for interval in jitteredIntervals {
            timestamp += interval
            estimate = estimator.tap(at: timestamp)
        }

        let finalEstimate = try XCTUnwrap(estimate)
        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 120.0, accuracy: 1.5)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testSimulated128BPMWithHumanJitter() throws {
        var estimator = TempoEstimator()
        let targetInterval = 60.0 / 128.0
        let jitteredIntervals: [TimeInterval] = (0..<12).map { index in
            let swing = (index.isMultiple(of: 2) ? 1.03 : 0.97)
            return targetInterval * swing
        }

        var estimate: TempoEstimate?
        var timestamp: TimeInterval = 0.0
        estimate = estimator.tap(at: timestamp)
        for interval in jitteredIntervals {
            timestamp += interval
            estimate = estimator.tap(at: timestamp)
        }

        let finalEstimate = try XCTUnwrap(estimate)
        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 128.0, accuracy: 1.5)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testSimulatedOddTupleAlternatingIntervals() throws {
        var estimator = TempoEstimator()
        // Long-short pairs that average to 120 BPM (0.5s) but each side alone would fail a tight gate.
        let tupleIntervals: [TimeInterval] = [0.75, 0.25, 0.75, 0.25, 0.75, 0.25, 0.75, 0.25, 0.75, 0.25]

        var estimate: TempoEstimate?
        var timestamp: TimeInterval = 0.0
        estimate = estimator.tap(at: timestamp)
        for interval in tupleIntervals {
            timestamp += interval
            estimate = estimator.tap(at: timestamp)
        }

        let finalEstimate = try XCTUnwrap(estimate)
        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 120.0, accuracy: 2.0)
        XCTAssertEqual(finalEstimate.acceptedIntervalCount, tupleIntervals.count)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testBackwardTimestampDoesNotRewindAnchorAndNextTapRecovers() throws {
        var estimator = TempoEstimator()
        _ = estimator.tap(at: 0.0)
        _ = estimator.tap(at: 0.5)
        let before = estimator.tap(at: 1.0)
        XCTAssertEqual(try XCTUnwrap(before.bpm), 120.0, accuracy: 0.001)

        let rewound = estimator.tap(at: 0.2)
        XCTAssertFalse(rewound.intervalAccepted)
        XCTAssertEqual(rewound.status, .outlierIgnored)
        XCTAssertEqual(rewound.tapCount, before.tapCount)
        XCTAssertEqual(rewound.acceptedIntervalCount, before.acceptedIntervalCount)
        XCTAssertEqual(rewound.bpm, before.bpm)

        let zeroTap = estimator.tap(at: 1.0)
        XCTAssertFalse(zeroTap.intervalAccepted)
        XCTAssertEqual(zeroTap.tapCount, before.tapCount)
        XCTAssertEqual(zeroTap.acceptedIntervalCount, before.acceptedIntervalCount)

        // Anchor is still 1.0, so the next even tap is a clean 0.5s interval.
        let recovered = estimator.tap(at: 1.5)
        XCTAssertTrue(recovered.intervalAccepted)
        XCTAssertEqual(try XCTUnwrap(recovered.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(recovered.tapCount, before.tapCount + 1)
        XCTAssertEqual(recovered.acceptedIntervalCount, before.acceptedIntervalCount + 1)
        XCTAssertEqual(recovered.status, .firstEstimate)
    }

    func testNonFiniteTimestampDoesNotPoisonStateAndNextTapRecovers() throws {
        var estimator = TempoEstimator()
        _ = estimator.tap(at: 0.0)
        _ = estimator.tap(at: 0.5)
        let before = estimator.tap(at: 1.0)
        XCTAssertEqual(try XCTUnwrap(before.bpm), 120.0, accuracy: 0.001)

        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            let ignored = estimator.tap(at: bad)
            XCTAssertFalse(ignored.intervalAccepted)
            XCTAssertEqual(ignored.tapCount, before.tapCount)
            XCTAssertEqual(ignored.acceptedIntervalCount, before.acceptedIntervalCount)
            XCTAssertEqual(ignored.bpm, before.bpm)
        }

        let recovered = estimator.tap(at: 1.5)
        XCTAssertTrue(recovered.intervalAccepted)
        XCTAssertEqual(try XCTUnwrap(recovered.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(recovered.tapCount, before.tapCount + 1)
        XCTAssertEqual(recovered.acceptedIntervalCount, before.acceptedIntervalCount + 1)
    }

    func testNonFiniteFirstTapLeavesEstimatorIdle() {
        var estimator = TempoEstimator()
        let ignored = estimator.tap(at: Double.nan)
        XCTAssertFalse(ignored.intervalAccepted)
        XCTAssertEqual(ignored.tapCount, 0)
        XCTAssertEqual(ignored.acceptedIntervalCount, 0)
        XCTAssertNil(ignored.bpm)

        let first = estimator.tap(at: 10.0)
        XCTAssertEqual(first.status, .waitingForSecondTap)
        XCTAssertEqual(first.tapCount, 1)
    }

    func testCleanTapAfterOutlierKeepsRunAlive() throws {
        var estimator = TempoEstimator()
        _ = estimator.tap(at: 0.0)
        _ = estimator.tap(at: 0.5)
        _ = estimator.tap(at: 1.0)
        let stableEstimate = estimator.tap(at: 1.5)

        let outlierEstimate = estimator.tap(at: 2.5)
        let recoveredEstimate = estimator.tap(at: 3.0)

        XCTAssertEqual(outlierEstimate.status, .outlierIgnored)
        XCTAssertFalse(outlierEstimate.intervalAccepted)
        XCTAssertEqual(try XCTUnwrap(recoveredEstimate.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(recoveredEstimate.tapCount, stableEstimate.tapCount + 1)
        XCTAssertEqual(recoveredEstimate.acceptedIntervalCount, stableEstimate.acceptedIntervalCount + 1)
        XCTAssertEqual(recoveredEstimate.status, .stableEstimate)
    }
}
