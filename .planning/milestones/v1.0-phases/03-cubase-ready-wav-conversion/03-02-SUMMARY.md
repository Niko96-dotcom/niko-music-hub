---
phase: 03-cubase-ready-wav-conversion
plan: "02"
subsystem: audio-conversion
tags: [swift, ffmpeg, process-runner, wav, xctest]
requires:
  - phase: 03-cubase-ready-wav-conversion
    provides: native conversion models, output naming, and WAVOutputVerifier from 03-01
provides:
  - Shared ExternalProcessRunning port and Foundation Process runner
  - FFmpegHealthChecker with missing, available, and unusable helper states
  - FFmpegAudioConverter with exact argv construction, temp output, verification, and cleanup
  - AudioConversionPipeline that tries native first and falls back to FFmpeg per file
  - Typed unsupported bit-depth and missing-FFmpeg conversion errors
affects: [audio-converter, helper-tools, batch-conversion, phase-05-downloader]
tech-stack:
  added: [Foundation Process adapter, FFmpeg argv adapter]
  patterns: [executableURL-plus-arguments process boundary, native-first fallback pipeline, helper-health-gated recoverable failures]
key-files:
  created:
    - Sources/AppCore/Services/ExternalProcessRunning.swift
    - Sources/FeatureAudioConverter/FFmpegHealthChecker.swift
    - Sources/FeatureAudioConverter/FFmpegAudioConverter.swift
    - Sources/FeatureAudioConverter/AudioConversionPipeline.swift
    - Tests/AppCoreTests/ExternalProcessRunningTests.swift
    - Tests/FeatureAudioConverterTests/FFmpegHealthTests.swift
    - Tests/FeatureAudioConverterTests/FFmpegAudioConverterTests.swift
    - Tests/FeatureAudioConverterTests/AudioConversionPipelineTests.swift
  modified:
    - Sources/FeatureAudioConverter/AudioConversionModels.swift
key-decisions:
  - "External helper execution is centralized behind ExternalProcessRunning using Process.executableURL and argument arrays."
  - "FFmpeg fallback writes temporary WAV output and returns only after WAVOutputVerifier accepts the file."
  - "Native conversion is attempted first; missing FFmpeg becomes a recoverable per-file error only for files that need fallback."
patterns-established:
  - "Helper adapters receive executable URLs and argument arrays rather than command strings."
  - "FFmpeg health checks are typed as missing, available, or unusable before fallback conversion."
  - "AudioConversionPipeline composes native and FFmpeg converters behind the shared AudioConverting protocol."
requirements-completed: ["CONV-02", "CONV-04", "CONV-05"]
duration: 9 min
completed: 2026-05-05
---

# Phase 03 Plan 02: FFmpeg Adapter Fallback with Health Check Summary

**Native-first WAV conversion fallback using a safe Process runner, FFmpeg health checks, exact argv construction, and reusable output verification**

## Performance

- **Duration:** 9 min
- **Started:** 2026-05-05T07:33:03Z
- **Completed:** 2026-05-05T07:41:51Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Added a shared `ExternalProcessRunning` port with typed request/result values and a Foundation-backed `Process` runner.
- Added `FFmpegHealthChecker` so missing or unusable helper state can be handled before fallback conversion.
- Added `FFmpegAudioConverter` that builds exact FFmpeg arguments, writes `.tmp.wav`, verifies output metadata, moves only verified files, and cleans up failures.
- Added `AudioConversionPipeline` so conversion tries native first and falls back to FFmpeg only when appropriate.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add shared external process runner and FFmpeg health checker** - `862e86a` (feat)
2. **Task 2: Implement FFmpegAudioConverter with exact safe argv** - `af451d3` (feat)
3. **Task 3: Add native-first conversion pipeline with recoverable fallback failures** - `8fa282b` (feat)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Sources/AppCore/Services/ExternalProcessRunning.swift` - Shared process runner contract and Foundation `Process` implementation.
- `Sources/FeatureAudioConverter/FFmpegHealthChecker.swift` - FFmpeg helper availability checks using configured helper paths.
- `Sources/FeatureAudioConverter/FFmpegAudioConverter.swift` - FFmpeg fallback adapter with exact argv, temp-file output, verifier gate, and cleanup.
- `Sources/FeatureAudioConverter/AudioConversionPipeline.swift` - Native-first conversion orchestration with recoverable missing-helper errors.
- `Sources/FeatureAudioConverter/AudioConversionModels.swift` - Adds typed unsupported bit-depth and missing-FFmpeg errors.
- `Tests/AppCoreTests/ExternalProcessRunningTests.swift` - Request/result and source-scan coverage for process execution.
- `Tests/FeatureAudioConverterTests/FFmpegHealthTests.swift` - Missing, available, unusable, and runner-throwing health cases.
- `Tests/FeatureAudioConverterTests/FFmpegAudioConverterTests.swift` - Exact argv, codecs, nonzero exit, verification, cleanup, unsupported bit depth, and source-scan tests.
- `Tests/FeatureAudioConverterTests/AudioConversionPipelineTests.swift` - Native success, fallback, missing FFmpeg, and verified-spec propagation tests.

## Decisions Made

- Process execution is centralized in `AppCore` so FFmpeg now follows the same safe boundary future yt-dlp adapters should use.
- The fallback adapter resolves 24-bit output to `pcm_s24le` and 16-bit output to `pcm_s16le`; unsupported bit depths fail before launch.
- The pipeline treats missing FFmpeg as a recoverable conversion error for the current file rather than a batch-wide failure.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- One pair of focused SwiftPM tests was initially launched concurrently, causing one process to wait on the `.build` lock. Verification was rerun sequentially afterward.
- The SDK roadmap updater marked the plan checklist but left the Phase 3 progress row stale; the row was corrected to `2/4` to match summaries on disk.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ExternalProcessRunningTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FFmpegHealthTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FFmpegAudioConverterTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioConversionPipelineTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 72 tests.
- `rg -n '"/bin/sh"|"sh"\s*,\s*"-c"|shell' Sources/AppCore Sources/FeatureAudioConverter` returned no matches.

## User Setup Required

None - no external service configuration required.

## Auth Gates

None.

## Known Stubs

None - stub scan found only initialized test recorder arrays and optional nil defaults, not UI placeholders or disconnected data paths.

## Next Phase Readiness

Plan 03-03 can build batch conversion UI and job orchestration against `AudioConversionPipeline`, with native-first behavior, per-file missing-helper errors, and verified FFmpeg output already covered by tests.

## Self-Check: PASSED

- Summary file exists.
- Key created files exist: `ExternalProcessRunning.swift`, `FFmpegHealthChecker.swift`, `FFmpegAudioConverter.swift`, and `AudioConversionPipeline.swift`.
- Task commits exist: `862e86a`, `af451d3`, and `8fa282b`.

---
*Phase: 03-cubase-ready-wav-conversion*
*Completed: 2026-05-05*
