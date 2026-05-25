---
phase: 03-cubase-ready-wav-conversion
plan: "01"
subsystem: audio-conversion
tags: [swift, avfoundation, avfaudio, wav, pcm, xctest]
requires:
  - phase: 02-bpm-tapper
    provides: validated feature-target and XCTest patterns
provides:
  - FeatureAudioConverter SwiftPM target and tests
  - Cubase-ready default AudioPreset with preserve-mono/stereo channel policy
  - Conversion request/result/spec models for native and FFmpeg paths
  - Deterministic WAV output naming with collision counters
  - WAVOutputVerifier metadata gate for file existence, WAV/PCM format, sample rate, bit depth, and channel count
  - NativeAudioConverter that writes temp WAV files and moves only verified outputs
affects: [audio-converter, wav-output, phase-04-recorder, output-inbox-readiness]
tech-stack:
  added: [AVFoundation AVAudioFile, AVAudioConverter, WAV PCM settings]
  patterns: [temp-file-then-verify conversion, preset-derived WAV specs, injected file-existence checks]
key-files:
  created:
    - Sources/FeatureAudioConverter/FeatureAudioConverter.swift
    - Sources/FeatureAudioConverter/AudioConversionModels.swift
    - Sources/FeatureAudioConverter/OutputFileNamer.swift
    - Sources/FeatureAudioConverter/WAVOutputVerifier.swift
    - Sources/FeatureAudioConverter/NativeAudioConverter.swift
    - Tests/FeatureAudioConverterTests/AudioPresetTests.swift
    - Tests/FeatureAudioConverterTests/OutputFileNamerTests.swift
    - Tests/FeatureAudioConverterTests/WAVOutputVerifierTests.swift
    - Tests/FeatureAudioConverterTests/NativeAudioConverterTests.swift
  modified:
    - Package.swift
    - Sources/AppCore/Settings/AudioPreset.swift
    - Tests/AppCoreTests/SettingsStoreTests.swift
key-decisions:
  - "The default audio preset is 44.1 kHz, 24-bit, and preserve mono/stereo."
  - "Native conversion writes `.tmp.wav` files and moves them only after WAVOutputVerifier passes."
  - "WAV metadata verification is a reusable service for conversion now and recorder output later."
patterns-established:
  - "Conversion output specs are derived from AudioPreset plus resolved channel count."
  - "Output names use `Source Name - 44100Hz 24bit.wav` with numbered collision suffixes."
  - "AVAudioConverter work streams bounded buffers instead of loading full files."
requirements-completed: ["CONV-02", "CONV-03", "CONV-05"]
duration: 10 min
completed: 2026-05-05
---

# Phase 03 Plan 01: Audio Preset Model and Native Conversion Path Summary

**Native Cubase-ready WAV core using AudioPreset defaults, deterministic filenames, temp-file conversion, and metadata verification**

## Performance

- **Duration:** 10 min
- **Started:** 2026-05-05T07:17:34Z
- **Completed:** 2026-05-05T07:27:33Z
- **Tasks:** 4
- **Files modified:** 12

## Accomplishments

- Added the `FeatureAudioConverter` library and test target without registering it in the app executable.
- Updated the shared `AudioPreset` default and settings test to 44.1 kHz, 24-bit, preserve mono/stereo.
- Added conversion models, supported source types, native/FFmpeg path markers, WAV specs, results, and typed conversion errors.
- Added deterministic output naming with preset suffixes and numbered collision handling.
- Added `WAVOutputVerifier` to reject missing, non-WAV/non-PCM, sample-rate, bit-depth, and channel-count mismatches.
- Added `NativeAudioConverter` using `AVAudioConverter`, bounded buffers, `.tmp.wav` output, verification-before-move, and failure cleanup.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add FeatureAudioConverter target and explicit channel policy** - `7987f6b` (feat)
2. **Task 2: Add conversion models and output naming** - `cc1dfa4` (feat)
3. **Task 3: Add reusable WAV metadata verifier** - `b328778` (feat)
4. **Task 4: Implement native AVFAudio converter with temp-file safety** - `889300d` (feat)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Package.swift` - Adds the `FeatureAudioConverter` library and test target.
- `Sources/AppCore/Settings/AudioPreset.swift` - Adds `preserveMonoStereo` and sets Cubase-ready defaults.
- `Tests/AppCoreTests/SettingsStoreTests.swift` - Aligns persisted default assertions to preserve mono/stereo.
- `Sources/FeatureAudioConverter/FeatureAudioConverter.swift` - Module bridge for converter tests and target compilation.
- `Sources/FeatureAudioConverter/AudioConversionModels.swift` - Supported types, converter paths, requests, specs, results, and errors.
- `Sources/FeatureAudioConverter/OutputFileNamer.swift` - Preset-suffixed output naming with collision counters.
- `Sources/FeatureAudioConverter/WAVOutputVerifier.swift` - WAV/PCM metadata verification service.
- `Sources/FeatureAudioConverter/NativeAudioConverter.swift` - Native streaming converter with temp-file safety.
- `Tests/FeatureAudioConverterTests/*.swift` - Focused tests for preset defaults, naming, verification, and native conversion.

## Decisions Made

- Default conversion uses the selected `AudioPreset` sample rate and bit depth, with preserve mono/stereo resolving mono sources to 1 channel and all wider sources to 2 channels.
- The native converter writes into the output directory using a unique `.tmp.wav` name and only moves the file to the planned final URL after verification passes.
- The verifier uses AVAudioFile metadata plus extension/container checks rather than trusting file names or successful writes alone.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added a converter module bridge for the new SwiftPM target**
- **Found during:** Task 1 (Add FeatureAudioConverter target and explicit channel policy)
- **Issue:** The new SwiftPM target needed a source file to build before the planned model files were introduced in Task 2, and `AudioPresetTests` needed to exercise the shared preset through the new feature test target.
- **Fix:** Added `Sources/FeatureAudioConverter/FeatureAudioConverter.swift` to re-export `AppCore` for the target and tests.
- **Files modified:** `Sources/FeatureAudioConverter/FeatureAudioConverter.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioPresetTests` passed.
- **Committed in:** `7987f6b`

**2. [Rule 3 - Blocking] Fixed Swift 6 sendability for WAVOutputVerifier file checks**
- **Found during:** Task 3 (Add reusable WAV metadata verifier)
- **Issue:** Storing `FileManager` inside a `Sendable` verifier failed Swift 6 compilation because `FileManager` is not Sendable.
- **Fix:** Replaced the stored `FileManager` with an injected `@Sendable` file-existence closure while keeping the default behavior backed by `FileManager.default`.
- **Files modified:** `Sources/FeatureAudioConverter/WAVOutputVerifier.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WAVOutputVerifierTests` passed.
- **Committed in:** `b328778`

---

**Total deviations:** 2 auto-fixed (2 blocking).
**Impact on plan:** Both fixes were required for the planned SwiftPM target and Swift 6 test suite to compile. No feature scope was expanded.

## Issues Encountered

- The AVAudioConverter input block initially produced Swift sendability warnings when it captured mutable local state. The implementation now isolates that state in a small unchecked-Sendable helper and focused tests remain green.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioPresetTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SettingsStoreTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputFileNamerTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WAVOutputVerifierTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NativeAudioConverterTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureAudioConverterTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 53 tests.
- `rg -n "AVAudioFile|AVAudioConverter|WAVOutputVerifier" Sources/FeatureAudioConverter` returned matches.

## User Setup Required

None - no external service configuration required.

## Auth Gates

None.

## Known Stubs

None - stub scan found no TODO/FIXME/placeholder text or hardcoded empty UI data flows in created/modified files.

## Next Phase Readiness

Plan 03-02 can build the FFmpeg fallback against the same `AudioConverting` contract, output spec, naming service, and `WAVOutputVerifier`. Phase 4 recording can reuse the verifier contract for recorder WAV readiness.

## Self-Check: PASSED

- Summary file exists.
- Key created files exist: `AudioConversionModels.swift`, `WAVOutputVerifier.swift`, and `NativeAudioConverter.swift`.
- Task commits exist: `7987f6b`, `cc1dfa4`, `b328778`, and `889300d`.

---
*Phase: 03-cubase-ready-wav-conversion*
*Completed: 2026-05-05*
