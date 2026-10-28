# BPM tapper algorithm

Short reference for `TempoEstimator` in `Sources/FeatureBPMTapper/TempoEstimator.swift`.

## The estimate

The tempo is the slope of a least-squares line of **tap time over beat number**, fitted to the
run's start tap and the last 12 accepted taps. BPM = 60 / slope.

Why a line and not an average of the intervals: a person tapping along to a song lands early or
late around the song's fixed beat grid, and those errors do not add up. Each tap's error appears
in two neighbouring intervals with opposite signs. The slope cancels it; the median of the
intervals (the estimator before 1.9.1) keeps every tap's jitter in the result. Simulated root-mean-
square error after 13 taps along to a song, Gaussian per-tap jitter:

| Song | Jitter per tap | Median of intervals | Fitted slope |
|------|----------------|---------------------|--------------|
| 120 BPM | 25 ms | ±1.7 | ±0.4 |
| 120 BPM | 40 ms | ±2.9 | ±0.7 |
| 140 BPM | 40 ms | ±3.9 | ±1.2 |
| 120 BPM | 60 ms | ±4.3 | ±2.9 |
| 140 BPM | 60 ms | ±5.8 | ±6.2 |
| 120 BPM, one missed beat | 35 ms | ±3.1 | ±0.7 |

Free tapping with no song (errors random-walk) comes out about equal for both estimators. At
60 ms jitter, which is very loose, the two are on par and the fit restarts a run spuriously in a
few percent of runs; at ordinary jitter it does not.

## Beat numbers

Every accepted tap carries a whole beat number. The first two spaced taps after the run's start
are beats 1 and 2; from the third accepted tap on, the fitted grid decides:

| Where the tap lands on the grid | Decision |
|---------------------------------|----------|
| Within half a beat of the next beat | The next beat (`outlierTolerance` = 0.5 beat, the old ±50 % interval band in beat units) |
| Within a quarter beat of a later beat | A **missed beat**: counts the beats it skipped. The band is tighter because a wrong beat number costs far more than one ignored tap |
| Anywhere else | Ignored. The readout keeps its value |

Beat numbers are only ever whole. A tap exactly between two beats (a 3:1 dotted pattern, a
mid-beat double tap) is ambiguous for any beat-counting estimator and is ignored; 2:1 triplet swing
reads the underlying beat, and that is the supported limit.

## Gates (unchanged in spirit)

- Valid tap spacing: **0.24 s–2.0 s** (25–250 BPM). Outside it the tap is ignored.
- Pause reset: **2.5 s** since the last tap (accepted or ignored) starts a new run.
- Stable after **4** accepted intervals.
- The pause and tempo-change rules measure from the last tap of any kind, so one stray tap does
  not make every following interval look long.

## Tempo change

A tap that is not the next beat (ignored or a missed beat) records its spacing from the previous
tap. **Three such taps in a row at one spacing** (within ±50 % of each other) are a new tempo:
the run restarts from those four taps as beats 0–3. Two are not enough: after two taps a missed
beat and a tempo change by 1.5× look identical, and so do two exact two-beat gaps and half-time
tapping. So 120 → 75 BPM is detected on the third slow tap and half-time tapping on the third
two-beat gap, while a single missed beat never restarts the run.

## Tests

`Tests/FeatureBPMTapperTests/TempoEstimatorTests.swift`: simulated 120 and 128 BPM with jitter
(±0.3 / ±0.1), a 13-tap loose run along to a 128 BPM song where the median reads 124.4 and the
fit 128.1, a missed beat with and without jitter, 2:1 swing, a stray mid-beat tap, the 120 → 75
and half-time changes, and the clock-glitch cases.
