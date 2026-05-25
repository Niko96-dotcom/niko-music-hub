---
phase: 03-cubase-ready-wav-conversion
plan: "03"
subsystem: audio-conversion-ui
tags: [swift, swiftui, wav, batch-conversion, output-inbox, xctest]
requires:
  - phase: 03-cubase-ready-wav-conversion
    provides: native conversion models, WAV verifier, FFmpeg fallback, and native-first pipeline from 03-01 and 03-02
provides:
  - WAV Converter ToolFeature registration through the existing feature registry boundary
  - Drag/drop and choose-file intake for M4A, MP3, WAV, AIFF/AIF, and FLAC sources
  - Non-recursive folder intake scanner with unsupported-row reporting and ignored-subfolder notices
  - Sequential batch conversion use case with stop-after-current and per-file outcomes
  - Verified-output-only output inbox writes with source/spec/converter metadata
  - Compact SwiftUI converter surface with preset strip, batch rows, recoverable errors, and source-scan coverage
affects: [audio-converter, output-inbox, phase-03-04-output-handoff, phase-04-recorder]
tech-stack:
  added: [SwiftUI fileImporter, UniformTypeIdentifiers fileURL drop intake]
  patterns: [feature-registered tool UI, scanner-to-viewmodel rows, use-case-owned batch loop, verified-only inbox writes]
key-files:
  created:
    - Sources/FeatureAudioConverter/AudioConverterFeature.swift
    - Sources/FeatureAudioConverter/AudioFileIntakeScanner.swift
    - Sources/FeatureAudioConverter/BatchAudioConversionUseCase.swift
    - Tests/FeatureAudioConverterTests/AudioConverterFeatureTests.swift
    - Tests/FeatureAudioConverterTests/AudioFileIntakeScannerTests.swift
    - Tests/FeatureAudioConverterTests/BatchAudioConversionUseCaseTests.swift
    - Tests/FeatureAudioConverterTests/AudioConverterViewModelTests.swift
  modified:
    - Package.swift
    - Sources/OutsideCubaseHub/AppComposition.swift
    - Sources/FeatureAudioConverter/AudioConverterViewModel.swift
    - Sources/FeatureAudioConverter/AudioConverterView.swift
key-decisions:
  - "The WAV Converter registers as a normal ToolFeature with id wav-converter and capabilities producesFiles/runsJobs."
  - "Dropped folders scan only top-level supported files; subfolders produce notices and are not scanned."
  - "Batch conversion writes output inbox items only for verified results returned by the native-first conversion pipeline."
  - "The converter UI includes source scans to keep Phase 3 copy in scope and exclude trim/fade/loudness/downloader/recording language."
patterns-established:
  - "Feature UI rows use deterministic AudioConverterRowState values for queued, converting, verified, failed, unsupported, and skipped."
  - "Stop-after-current is modeled as a controller checked between sequential file conversions."
  - "Output inbox metadata uses sourceFile, sampleRate, bitDepth, channels, converter, and sourceType keys."
requirements-completed: ["CONV-01", "CONV-02", "CONV-03", "CONV-04", "CONV-05"]
duration: 13 min
completed: 2026-05-05
---

# Phase 03 Plan 03: Batch Conversion UI and Output Validation Summary

**Registry-backed WAV Converter with top-level audio intake, sequential native-first batch conversion, stop-after-current, verified-only inbox writes, and compact SwiftUI rows**

## Performance

- **Duration:** 13 min
- **Started:** 2026-05-05T07:46:45Z
- **Completed:** 2026-05-05T07:59:59Z
- **Tasks:** 5
- **Files modified:** 11

## Accomplishments

- Registered `AudioConverterFeature` through `AppComposition` without converter-specific shell branching.
- Added `AudioFileIntakeScanner` for M4A, MP3, WAV, AIFF/AIF, and FLAC, including unsupported rows and one-level folder scanning.
- Added `BatchAudioConversionUseCase` that loads settings, converts files sequentially through `AudioConversionPipeline`, handles stop-after-current, and writes only verified outputs to the shared output inbox.
- Added `AudioConverterViewModel` row states and exact UI-SPEC recovery copy for queued, converting, verified, failed, unsupported, and skipped rows.
- Replaced the temporary converter view with a compact SwiftUI surface containing drag/choose intake, preset strip, batch rows, recovery actions, and required copy/source scans.

## Task Commits

Each task was committed atomically:

1. **Task 1: Register WAV Converter as a ToolFeature** - `1b1e310` (feat)
2. **Task 2: Add supported audio intake scanner** - `02d8bfd` (feat)
3. **Task 3: Add batch conversion use case and stop-after-current behavior** - `038ee9e` (feat)
4. **Task 4: Add converter row-state view model** - `a996486` (feat)
5. **Task 5: Render compact converter UI with preset strip and batch rows** - `ad31660` (feat)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Package.swift` - Adds `FeatureAudioConverter` to the app executable target.
- `Sources/OutsideCubaseHub/AppComposition.swift` - Imports and registers `AudioConverterFeature()` after the BPM tapper.
- `Sources/FeatureAudioConverter/AudioConverterFeature.swift` - Provides WAV Converter metadata and view factory.
- `Sources/FeatureAudioConverter/AudioFileIntakeScanner.swift` - Scans supported files and top-level folder contents only.
- `Sources/FeatureAudioConverter/BatchAudioConversionUseCase.swift` - Runs sequential conversion, stop-after-current, progress updates, and verified-only output inbox writes.
- `Sources/FeatureAudioConverter/AudioConverterViewModel.swift` - Owns converter row state, intake, batch handoff, stop-after-current, retry, and UI copy.
- `Sources/FeatureAudioConverter/AudioConverterView.swift` - Renders the compact SwiftUI converter surface.
- `Tests/FeatureAudioConverterTests/AudioConverterFeatureTests.swift` - Covers feature metadata and capabilities.
- `Tests/FeatureAudioConverterTests/AudioFileIntakeScannerTests.swift` - Covers supported extensions, unsupported files, and top-level-only folder drops.
- `Tests/FeatureAudioConverterTests/BatchAudioConversionUseCaseTests.swift` - Covers missing FFmpeg row isolation, stop-after-current, and verified-only inbox writes.
- `Tests/FeatureAudioConverterTests/AudioConverterViewModelTests.swift` - Covers row creation, button enablement, recovery copy, stop handoff, and UI source scans.

## Decisions Made

- The converter remains behind the feature boundary; no app shell branching was added.
- The intake scanner accepts AIF as an AIFF alias while preserving the v1 supported source set.
- The batch use case treats `ConversionResult` as the verified contract because native and FFmpeg converters already verify before returning.
- The UI includes `Reveal in Finder` for verified rows using the existing `FileActions` boundary; drag-out polish remains for Plan 03-04.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added temporary converter view/view-model scaffolding during feature registration**
- **Found during:** Task 1 (Register WAV Converter as a ToolFeature)
- **Issue:** `AudioConverterFeature.makeView(context:)` had to return `AudioConverterView(context:viewModel:)`, but those types did not exist until later planned tasks.
- **Fix:** Added minimal compiling `AudioConverterView` and `AudioConverterViewModel` in Task 1, then replaced them with full implementations in Tasks 4 and 5.
- **Files modified:** `Sources/FeatureAudioConverter/AudioConverterView.swift`, `Sources/FeatureAudioConverter/AudioConverterViewModel.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioConverterFeatureTests` passed.
- **Committed in:** `1b1e310`

**2. [Rule 1 - Bug] Fixed folder scanner test URL spelling**
- **Found during:** Task 2 (Add supported audio intake scanner)
- **Issue:** `FileManager.contentsOfDirectory` returned `/private/var/...` URLs while the fixture path used `/var/...`, causing a false failure unrelated to scanner behavior.
- **Fix:** Updated the folder test to compare top-level file identities by filename while preserving coverage for supported and unsupported rows.
- **Files modified:** `Tests/FeatureAudioConverterTests/AudioFileIntakeScannerTests.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioFileIntakeScannerTests` passed.
- **Committed in:** `02d8bfd`

**3. [Rule 3 - Blocking] Fixed SwiftUI conditional style and drop helper actor isolation**
- **Found during:** Task 5 (Render compact converter UI with preset strip and batch rows)
- **Issue:** SwiftUI could not type-check a ternary `.buttonStyle(...)` expression, and the drop URL decoder inherited main-actor isolation from `View`.
- **Fix:** Split the convert button into a `@ViewBuilder` and marked the pure URL decoder `nonisolated`.
- **Files modified:** `Sources/FeatureAudioConverter/AudioConverterView.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioConverterViewModelTests` and full `swift test` passed.
- **Committed in:** `ad31660`

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking).
**Impact on plan:** All fixes were local to the planned files and necessary for reliable compilation/tests. No feature scope was expanded beyond the approved converter UI.

## Issues Encountered

- Running the focused SwiftPM filters in parallel caused later filters to wait on the `.build` lock. All filter runs completed successfully.
- The SDK roadmap updater checked off plan 03-03 but left the Phase 3 progress row at `2/4`; the row was corrected to `3/4` to match summaries on disk.
- Manual smoke verification was not run in this non-interactive executor. Automated tests and source scans passed; real drag/drop and Finder interaction remain best verified manually.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioConverterFeatureTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioFileIntakeScannerTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BatchAudioConversionUseCaseTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioConverterViewModelTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 85 tests.
- `rg -n "wav-converter|AudioConverterFeature" Sources/OutsideCubaseHub/AppShell` returned no matches.
- `rg -n "trim|fade|loudness|key analysis|downloader|recording|recursive" Sources/FeatureAudioConverter/AudioConverterView.swift` returned no matches.
- `rg -n "Drop audio files to convert|Add Audio Files|Convert to WAV|Stop After Current File|44.1 kHz - 24-bit - Preserve mono/stereo|Choose FFmpeg|Verified WAV ready" Sources/FeatureAudioConverter/AudioConverterView.swift` returned matches.

## User Setup Required

None - no external service configuration required.

## Auth Gates

None.

## Known Stubs

None - stub scan found only legitimate empty collection initializers and optional defaults for local row/test state. No placeholder/TODO/FIXME copy or disconnected UI data source was introduced.

## Next Phase Readiness

Plan 03-04 can build reveal/drag-out polish on top of verified converter rows and output inbox items. The row model already stores verified output URLs and converter metadata; the shared output inbox contains only `.available` verified WAV items.

## Self-Check: PASSED

- Summary file exists.
- Key created files exist: `AudioConverterFeature.swift`, `AudioFileIntakeScanner.swift`, `BatchAudioConversionUseCase.swift`, and `AudioConverterView.swift`.
- Task commits exist: `1b1e310`, `02d8bfd`, `038ee9e`, `a996486`, and `ad31660`.

---
*Phase: 03-cubase-ready-wav-conversion*
*Completed: 2026-05-05*
