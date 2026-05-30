# BPM tapper algorithm

Short reference for `TempoEstimator` in `Sources/FeatureBPMTapper/TempoEstimator.swift` (hub-polish wave D).

## What changed

| Area | Before | After |
|------|--------|--------|
| Central interval | Mean of recent accepted intervals | **Median** when three or more intervals are in the window; mean for the first two |
| Outlier band | ±35% of recent mean | **±50%** of recent median/mean so long–short tuple taps (e.g. 0.75s + 0.25s averaging to 120 BPM) stay in the run |
| Fast stray taps | Rejected only by min/max | Still rejected by min/max; **very short** intervals that double to the baseline are accepted (accidental double-tap between beats) |
| Missed beat | Sometimes accepted if 2× baseline | **Rejected** when the gap is ~2× the beat (e.g. 1.0s after a steady 0.5s) so tempo does not halve after one long pause |

## Why

- **Median** matches common tap-tempo apps: one bad tap moves the readout less than a mean.
- **Wider band + median** keeps simulated 120 / 128 BPM with human jitter and alternating long–short “tuple” taps within about ±1.5 BPM in tests.
- **Half-interval recovery** only for clearly short gaps avoids treating a skipped beat as a valid slow interval.

## Defaults (unchanged UX)

- Rolling window: last **12** accepted intervals
- Stable after **4** accepted intervals
- Pause reset: **2.5s**
- Valid tap spacing: **0.24s–2.0s** (25–250 BPM)

## Tests

`Tests/FeatureBPMTapperTests/TempoEstimatorTests.swift` — includes simulated 120 BPM, 128 BPM, and odd long–short tuple sequences.
