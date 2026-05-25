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
        let expectedBPM = 60.0 / ((0.50 + 0.60 + 0.60) / 3.0)
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
