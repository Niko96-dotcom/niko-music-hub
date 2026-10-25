import FeatureBPMTapper
import XCTest

final class TempoEstimatorTests: XCTestCase {
    /// Feeds `intervals` as consecutive taps starting at `start` and returns the last estimate.
    private func feed(
        _ intervals: [TimeInterval],
        into estimator: inout TempoEstimator,
        start: TimeInterval = 0.0
    ) -> TempoEstimate {
        var timestamp = start
        var estimate = estimator.tap(at: timestamp)
        for interval in intervals {
            timestamp += interval
            estimate = estimator.tap(at: timestamp)
        }
        return estimate
    }

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

    func testEstimateUsesEveryTapInTheWindow() throws {
        var estimator = TempoEstimator()
        // A symmetric tempo step: the fitted slope equals the mean interval here,
        // so the expected value is exact without re-deriving the fit.
        let intervals: [TimeInterval] = [0.50, 0.50, 0.50, 0.50, 0.60, 0.60, 0.60, 0.60]

        let finalEstimate = feed(intervals, into: &estimator)

        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 60.0 / 0.55, accuracy: 0.001)
        XCTAssertEqual(finalEstimate.acceptedIntervalCount, 8)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testWindowDropsTheOldestTapAfterConfiguredLimit() throws {
        let configuration = TempoEstimatorConfiguration(recentIntervalLimit: 3)
        var windowed = TempoEstimator(configuration: configuration)
        var freshOverKeptTaps = TempoEstimator(configuration: configuration)
        var unlimited = TempoEstimator()

        let windowedEstimate = feed([0.50, 0.50, 0.60, 0.60], into: &windowed)
        let keptEstimate = feed([0.50, 0.60, 0.60], into: &freshOverKeptTaps, start: 0.5)
        let unlimitedEstimate = feed([0.50, 0.50, 0.60, 0.60], into: &unlimited)

        XCTAssertEqual(windowedEstimate.acceptedIntervalCount, 3)
        XCTAssertEqual(windowedEstimate.tapCount, 5)
        XCTAssertEqual(
            try XCTUnwrap(windowedEstimate.bpm),
            try XCTUnwrap(keptEstimate.bpm),
            accuracy: 0.001
        )
        let unlimitedBPM = try XCTUnwrap(unlimitedEstimate.bpm)
        let windowedBPM = try XCTUnwrap(windowedEstimate.bpm)
        XCTAssertGreaterThan(abs(unlimitedBPM - windowedBPM), 1.0)
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

    func testIgnoresTapBelowMinimumInterval() throws {
        var estimator = TempoEstimator()
        _ = estimator.tap(at: 0.0)
        _ = estimator.tap(at: 0.5)
        _ = estimator.tap(at: 1.0)

        let steadyEstimate = estimator.tap(at: 1.5)
        let outlierEstimate = estimator.tap(at: 1.58)

        XCTAssertEqual(try XCTUnwrap(steadyEstimate.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(outlierEstimate.bpm, steadyEstimate.bpm)
        XCTAssertEqual(outlierEstimate.tapCount, steadyEstimate.tapCount)
        XCTAssertEqual(outlierEstimate.acceptedIntervalCount, steadyEstimate.acceptedIntervalCount)
        XCTAssertEqual(outlierEstimate.status, .outlierIgnored)
        XCTAssertFalse(outlierEstimate.intervalAccepted)
    }

    func testStrayTapBetweenBeatsIsIgnoredAndRunContinues() throws {
        var estimator = TempoEstimator()
        let steady = feed([0.5, 0.5, 0.5, 0.5], into: &estimator)

        let stray = estimator.tap(at: 2.25)
        let recovered = estimator.tap(at: 2.5)

        XCTAssertEqual(stray.status, .outlierIgnored)
        XCTAssertFalse(stray.intervalAccepted)
        XCTAssertEqual(stray.tapCount, steady.tapCount)
        XCTAssertEqual(try XCTUnwrap(stray.bpm), 120.0, accuracy: 0.001)
        XCTAssertTrue(recovered.intervalAccepted)
        XCTAssertEqual(try XCTUnwrap(recovered.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(recovered.tapCount, steady.tapCount + 1)
        XCTAssertEqual(recovered.acceptedIntervalCount, steady.acceptedIntervalCount + 1)
        XCTAssertEqual(recovered.status, .stableEstimate)
    }

    func testMissedBeatCountsAsTwoBeats() throws {
        var estimator = TempoEstimator()
        let steady = feed([0.5, 0.5, 0.5], into: &estimator)

        let afterGap = estimator.tap(at: 2.5)
        let following = estimator.tap(at: 3.0)

        XCTAssertTrue(afterGap.intervalAccepted)
        XCTAssertEqual(afterGap.status, .stableEstimate)
        XCTAssertEqual(try XCTUnwrap(afterGap.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(afterGap.tapCount, steady.tapCount + 1)
        XCTAssertEqual(afterGap.acceptedIntervalCount, steady.acceptedIntervalCount + 1)
        XCTAssertEqual(try XCTUnwrap(following.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(following.tapCount, steady.tapCount + 2)
    }

    func testMissedBeatWithHumanJitterStaysWithinOneBPM() throws {
        var estimator = TempoEstimator()
        // 120 BPM taps with jitter; the beat at 2.0s is skipped.
        let taps: [TimeInterval] = [0.0, 0.51, 0.98, 1.52, 2.49, 3.01, 3.48, 4.02]

        var estimate: TempoEstimate?
        for tap in taps {
            estimate = estimator.tap(at: tap)
        }

        let finalEstimate = try XCTUnwrap(estimate)
        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 120.0, accuracy: 1.0)
        XCTAssertEqual(finalEstimate.tapCount, taps.count)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testSimulated120BPMWithHumanJitter() throws {
        var estimator = TempoEstimator()
        let jitteredIntervals: [TimeInterval] = [
            0.48, 0.52, 0.49, 0.51, 0.50, 0.50, 0.47, 0.53, 0.50, 0.50, 0.51, 0.49,
        ]

        let finalEstimate = feed(jitteredIntervals, into: &estimator)

        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 120.0, accuracy: 0.3)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testSimulated128BPMWithAlternatingJitter() throws {
        var estimator = TempoEstimator()
        let targetInterval = 60.0 / 128.0
        let jitteredIntervals: [TimeInterval] = (0..<12).map { index in
            let swing = (index.isMultiple(of: 2) ? 1.03 : 0.97)
            return targetInterval * swing
        }

        let finalEstimate = feed(jitteredIntervals, into: &estimator)

        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 128.0, accuracy: 0.1)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testLooseTappingAlongToASongReadsTheSongTempo() throws {
        var estimator = TempoEstimator()
        // 128 BPM with 40ms per-tap jitter around the song's beat grid (the
        // errors do not add up). The median interval of these taps reads 124.4;
        // the fitted slope reads 128.1.
        let taps: [TimeInterval] = [
            0.016, 0.598, 0.920, 1.426, 1.799, 2.347, 2.837, 3.312, 3.701, 4.300, 4.732, 5.156, 5.655,
        ]

        var estimate: TempoEstimate?
        for tap in taps {
            estimate = estimator.tap(at: tap)
        }

        let finalEstimate = try XCTUnwrap(estimate)
        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 128.0, accuracy: 0.6)
        XCTAssertEqual(finalEstimate.tapCount, taps.count)
        XCTAssertEqual(finalEstimate.status, .stableEstimate)
    }

    func testSwungTapsReadTheUnderlyingBeat() throws {
        var estimator = TempoEstimator()
        // 2:1 (triplet) swing at 120 BPM: every tap is late or early by a third of a beat.
        let swungIntervals: [TimeInterval] = (0..<10).map { $0.isMultiple(of: 2) ? 2.0 / 3.0 : 1.0 / 3.0 }

        let finalEstimate = feed(swungIntervals, into: &estimator)

        XCTAssertEqual(try XCTUnwrap(finalEstimate.bpm), 120.0, accuracy: 0.5)
        XCTAssertEqual(finalEstimate.acceptedIntervalCount, swungIntervals.count)
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

    func testSteadySlowerTempoStartsNewRunAfterThreeTaps() throws {
        var estimator = TempoEstimator()
        _ = feed([0.5, 0.5, 0.5, 0.5], into: &estimator)

        // 120 → 75 BPM. After two slow taps a missed beat and a new tempo still
        // look alike; the third slow tap settles it.
        let firstSlow = estimator.tap(at: 2.8)
        XCTAssertEqual(firstSlow.status, .outlierIgnored)
        XCTAssertEqual(try XCTUnwrap(firstSlow.bpm), 120.0, accuracy: 0.001)

        let secondSlow = estimator.tap(at: 3.6)
        XCTAssertNotEqual(secondSlow.status, .longPauseReset)

        let switched = estimator.tap(at: 4.4)
        XCTAssertEqual(switched.status, .longPauseReset)
        XCTAssertTrue(switched.intervalAccepted)
        XCTAssertEqual(try XCTUnwrap(switched.bpm), 75.0, accuracy: 0.001)
        XCTAssertEqual(switched.acceptedIntervalCount, 3)
        XCTAssertEqual(switched.tapCount, 4)

        let following = estimator.tap(at: 5.2)
        XCTAssertTrue(following.intervalAccepted)
        XCTAssertEqual(try XCTUnwrap(following.bpm), 75.0, accuracy: 0.001)
        XCTAssertEqual(following.tapCount, 5)
    }

    func testHalfTimeTappingStartsNewRunAfterThreeGaps() throws {
        var estimator = TempoEstimator()
        _ = feed([0.5, 0.5, 0.5, 0.5], into: &estimator)

        // One or two exact two-beat gaps are missed beats at 120 BPM ...
        let firstGap = estimator.tap(at: 3.0)
        let secondGap = estimator.tap(at: 4.0)
        XCTAssertEqual(try XCTUnwrap(firstGap.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(firstGap.tapCount, 6)
        XCTAssertEqual(try XCTUnwrap(secondGap.bpm), 120.0, accuracy: 0.001)
        XCTAssertEqual(secondGap.tapCount, 7)

        // ... the third means the person taps 60 BPM.
        let switched = estimator.tap(at: 5.0)
        XCTAssertEqual(switched.status, .longPauseReset)
        XCTAssertEqual(try XCTUnwrap(switched.bpm), 60.0, accuracy: 0.001)
        XCTAssertEqual(switched.tapCount, 4)
        XCTAssertEqual(switched.acceptedIntervalCount, 3)
    }
}
