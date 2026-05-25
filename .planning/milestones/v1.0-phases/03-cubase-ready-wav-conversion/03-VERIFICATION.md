---
phase: 03-cubase-ready-wav-conversion
verified: 2026-05-06T17:10:25Z
status: human_needed
score: 15/15 must-haves verified
overrides_applied: 0
gaps: []
human_verification:
  - "Running app conversion flow with real M4A, MP3, WAV, AIFF, and FLAC files."
  - "Finder/Cubase drag smoke from converter rows and the shared output inbox."
  - "Output inbox live appearance after a conversion completes while the inspector is visible."
---

# Phase 3: Cubase-Ready WAV Conversion Verification Report

**Phase Goal:** Build the shared audio output pipeline by converting M4A/common audio files into verified WAV files.  
**Verified:** 2026-05-06T17:10:25Z  
**Status:** human_needed  
**Re-verification:** Yes - after 03-05 gap closure  
**Scope note:** Included gap-closure commits through `d05ffce` (`refactor(03-05): adapt preset editor layout`) plus the earlier post-review fix commit `33f4136`.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can drag or choose M4A and common audio files. | VERIFIED | `AudioConverterView` wires `.fileImporter` and `.onDrop` to `viewModel.addFileURLs`; `AudioFileIntakeScanner` supports `m4a`, `mp3`, `wav`, `aiff`/`aif`, and `flac`; tests cover supported intake. |
| 2 | Dropped folders scan top-level supported audio files only. | VERIFIED | `AudioFileIntakeScanner.scanFolder` uses `contentsOfDirectory` and counts subfolders instead of recursing; `testDroppedFolderScansTopLevelOnly` passed. |
| 3 | Default WAV output is Cubase-ready: 44.1 kHz, 24-bit, preserve mono/stereo. | VERIFIED | `AudioPreset.cubaseDefault` and initializer default to `44100`, `24`, `channelCount: 2`, `.preserveMonoStereo`; `AudioPresetTests` passed. |
| 4 | User can choose or edit sample rate, bit depth, and channel handling. | VERIFIED | `AudioConverterView` exposes `Edit WAV Preset` plus `Picker("Sample rate")`, `Picker("Bit depth")`, and `Picker("Channel handling")`; picker bindings call `viewModel.updateWAVPreset(sampleRate:bitDepth:channelMode:)`; `AudioConverterViewModel` persists through `context.settingsStore.updateSettings`; `AudioConverterViewModelTests` cover persisted settings, live summary text, queued filename refresh, and edited `ConversionRequest.preset`. |
| 5 | Conversion produces WAV PCM using the selected project preset. | VERIFIED | `ConversionRequest` carries `preset`; native conversion uses `AVSampleRateKey`, `AVLinearPCMBitDepthKey`, and `AVNumberOfChannelsKey`; FFmpeg argv uses `-ar`, `-ac`, and `pcm_s24le`/`pcm_s16le`. |
| 6 | App verifies output sample rate, bit depth, channel count, PCM/WAV format, and file existence. | VERIFIED | `WAVOutputVerifier.verify` checks file existence, `.wav` extension, `kAudioFormatLinearPCM`, sample rate, `mBitsPerChannel`, and channel count. |
| 7 | Native conversion writes temp files and returns only verified final WAVs. | VERIFIED | `NativeAudioConverter` writes `.tmp.wav`, verifies it, moves only after verification, and removes temp files on failure; `NativeAudioConverterTests` passed. |
| 8 | FFmpeg fallback uses safe executable URL plus argument array and verifies outputs. | VERIFIED | `FFmpegAudioConverter` builds `ExternalProcessRequest(executableURL:arguments:)`; `FoundationExternalProcessRunner` sets `Process.executableURL` and `.arguments`; production `rg` found no `/bin/sh` or `sh -c`. |
| 9 | Conversion tries native first and falls back to FFmpeg only when appropriate. | VERIFIED | `AudioConversionPipeline.convert` calls `native.convert` first and gates fallback by typed errors and FFmpeg health. |
| 10 | Missing FFmpeg fails only fallback-required files with helper guidance. | VERIFIED | Pipeline emits `FFmpeg is required for this file. Choose FFmpeg, then convert this file again.`; batch tests confirm affected-row-only failure. |
| 11 | Batch conversion shows per-file progress, success/error states, and stop-after-current. | VERIFIED | `BatchAudioConversionUseCase` emits `.converting`, `.verified`, `.failed`, and `.skipped`; `AudioConverterViewModel` applies updates and exposes `requestStopAfterCurrent`; tests passed. |
| 12 | Output names include source filename, preset suffix, and collision counters. | VERIFIED | `OutputFileNamer` produces `Source - 44100Hz 24bit.wav` and appends ` 2`, ` 3`, etc.; naming tests passed. |
| 13 | Verified outputs are recorded in the shared output inbox with metadata, and failed/unverified rows do not become ready items. | VERIFIED | `BatchAudioConversionUseCase.addOutputInboxItem` runs only after converter success and stores `sourceFile`, `sampleRate`, `bitDepth`, `channels`, `converter`, and `sourceType`; `testOnlyVerifiedOutputsAreAddedToInbox` passed. |
| 14 | WAV Converter is registered through the feature boundary. | VERIFIED | `AppComposition` imports `FeatureAudioConverter` and registers `AudioConverterFeature()`; the feature metadata id is `wav-converter` with `.producesFiles` and `.runsJobs`. |
| 15 | Converted outputs can be revealed or dragged from converter rows and the shared inbox. | VERIFIED programmatically; HUMAN smoke still needed | Converter rows and inbox rows use `OutputHandoff.dragFileURL` and `NSItemProvider(contentsOf:)`; reveal calls use `context.fileActions.revealInFinder`. Real Finder/Cubase drag was not manually run. |

**Score:** 15/15 truths verified; human smoke remains pending

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `Sources/FeatureAudioConverter/WAVOutputVerifier.swift` | Reusable metadata verifier | VERIFIED | 112 lines; substantive WAV/PCM/spec checks; used by native and FFmpeg converters. |
| `Sources/FeatureAudioConverter/NativeAudioConverter.swift` | Native AVFAudio converter | VERIFIED | 257 lines; streams through `AVAudioConverter`, writes `.tmp.wav`, verifies, then moves final output. |
| `Sources/FeatureAudioConverter/AudioConversionModels.swift` | Conversion models | VERIFIED | 133 lines; source type, converter path, request/result/spec, and typed errors. |
| `Sources/FeatureAudioConverter/FFmpegAudioConverter.swift` | Safe FFmpeg fallback | VERIFIED | 229 lines; explicit argv, temp file cleanup, verifier use, channel probing. |
| `Sources/FeatureAudioConverter/AudioConversionPipeline.swift` | Native-first fallback orchestration | VERIFIED | Calls native first, then health-gated FFmpeg fallback. |
| `Sources/AppCore/Services/ExternalProcessRunning.swift` | Shared process-running port | VERIFIED | Uses `Process.executableURL` and `arguments`; drains stdout/stderr pipes. |
| `Sources/FeatureAudioConverter/AudioConverterFeature.swift` | ToolFeature metadata and view factory | VERIFIED | The SDK line-count check flagged 22 lines vs. planned 35, but source is complete and wired. Not a stub. |
| `Sources/FeatureAudioConverter/AudioConverterViewModel.swift` | Batch converter UI state plus preset editing | VERIFIED | 498 lines; owns intake, conversion, progress, recoverable FFmpeg selection, handoff helpers, `currentAudioPreset`, `presetSummaryText`, and `updateWAVPreset`. |
| `Sources/FeatureAudioConverter/BatchAudioConversionUseCase.swift` | Batch conversion and inbox writes | VERIFIED | Uses settings, converter pipeline, progress updates, stop-after-current, and verified-only inbox writes. |
| `Sources/FeatureAudioConverter/AudioConverterView.swift` | Converter UI | VERIFIED | 424 lines; drag/drop, file importer, rows, progress, reveal, drag, live preset strip, and compact editable preset controls are present. |
| `Sources/AppCore/OutputInbox/OutputHandoff.swift` | Shared reveal/drag eligibility | VERIFIED with warning | Gates on `.available`, existing file, and `.wav`; does not re-verify stale/corrupted WAV metadata. |
| `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift` | Shared output inbox reveal/drag UI | VERIFIED with warning | Lists persisted items on appear, exposes reveal/drag for eligible WAVs and metadata; no live refresh after conversion add. |
| `Sources/OutsideCubaseHub/AppComposition.swift` | App integration | VERIFIED | Registers `AudioConverterFeature()` in the composition root through the feature registry. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Package.swift` | `FeatureAudioConverter` | SwiftPM target/product | WIRED | Library, executable dependency, and test target exist. |
| `NativeAudioConverter.swift` | `WAVOutputVerifier.swift` | `verifier.verify(url:expectedSpec:)` before move | WIRED | Verified temp spec controls final result. |
| `AudioPreset.swift` | `AudioConversionModels.swift` | `ConversionRequest.preset` and `WAVOutputSpec(preset:)` | WIRED | Sample rate and bit depth flow through request/spec. |
| `AudioConversionPipeline.swift` | `NativeAudioConverter.swift` | Default `native: NativeAudioConverter()` | WIRED | Native path attempted before fallback. |
| `FFmpegAudioConverter.swift` | `ExternalProcessRunning.swift` | `ExternalProcessRequest(executableURL:arguments:)` | WIRED | No command-string shell path in production source. |
| `FFmpegAudioConverter.swift` | `WAVOutputVerifier.swift` | Verifies temp output after successful process exit | WIRED | Verification failure blocks final output. |
| `AppComposition.swift` | `AudioConverterFeature.swift` | `AudioConverterFeature()` registration | WIRED | Registered after `BPMTapperFeature()`. |
| `AudioConverterViewModel.swift` | `BatchAudioConversionUseCase.swift` | `batchUseCase.convert(...)` | WIRED | View model starts batch conversion and applies updates. |
| `BatchAudioConversionUseCase.swift` | `OutputInboxItem.swift` | `OutputInboxItem(status: .available, metadata: ...)` | WIRED | Successful verified outputs become inbox items. |
| `AudioConverterView.swift` | `OutputHandoff.swift` | `row.verifiedOutputURLForDrag()` uses shared helper | WIRED | Failed/skipped rows have no drag provider. |
| `OutputInboxInspectorView.swift` | `OutputHandoff.swift` | `OutputHandoff.dragFileURL` and `isRevealable` | WIRED | Shared inbox reveal/drag is gated. |
| `AudioConverterView.swift` | `FileActions.swift` | `context.fileActions.revealInFinder(verifiedOutputURL)` | WIRED | Reveal action uses verified output URL. |
| `AudioConverterView.swift` | `AudioConverterViewModel.swift` | `viewModel.updateWAVPreset(sampleRate:bitDepth:channelMode:)` and `viewModel.presetSummaryText` | WIRED | Preset controls render and update live view-model state. |
| `AudioConverterViewModel.swift` | `SettingsStore.swift` | `context.settingsStore.updateSettings { settings.audioPreset = updatedPreset }` | WIRED | Preset edits persist into shared app settings. |
| `AudioConverterViewModel.swift` | `OutputFileNamer.swift` | `refreshQueuedOutputNames()` calls `plannedOutputName(for:)` | WIRED | Queued output names reflect edited preset values. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `AudioConverterView` | `viewModel.rows` | `.fileImporter` / `.onDrop` -> `addFileURLs` -> `AudioFileIntakeScanner.scan` | Yes | FLOWING |
| `AudioConverterView` | `viewModel.currentAudioPreset` | Preset pickers -> `updateWAVPreset` -> `SettingsStore.updateSettings` | Yes | FLOWING |
| `AudioConverterViewModel` | Row state/progress | `BatchAudioConversionUseCase.convert` progress callback and outcomes | Yes | FLOWING |
| `BatchAudioConversionUseCase` | `ConversionRequest` and inbox item | `settingsStore.loadSettings()` + selected files + converter result | Yes | FLOWING |
| `NativeAudioConverter` | `ConversionResult.spec` | `WAVOutputVerifier.verify` on temp WAV | Yes | FLOWING |
| `FFmpegAudioConverter` | `ConversionResult.spec` | FFmpeg process output -> `WAVOutputVerifier.verify` | Yes | FLOWING |
| `OutputInboxInspectorView` | `items` | `context.outputInboxStore.listItems()` on appear | Yes, but not live-updating | FLOWING with warning |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full codebase tests | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 103 tests, 0 failures | PASS |
| Editable preset source contract | `rg -n "Edit WAV Preset|Picker\\(\"Sample rate\"|Picker\\(\"Bit depth\"|Picker\\(\"Channel handling\"|updateWAVPreset|presetSummaryText" Sources/FeatureAudioConverter Tests/FeatureAudioConverterTests` | Expected matches in view, view model, and tests | PASS |
| Static preset strip removed | `rg -n 'Text\\("44\\.1 kHz - 24-bit - Preserve mono/stereo"\\)' Sources/FeatureAudioConverter/AudioConverterView.swift` | No matches | PASS |
| Production helper execution avoids shell | `rg -n '"/bin/sh"|sh -c|shell|Process\\(' Sources` | Only `Process()` in `ExternalProcessRunning.swift` | PASS |
| Data-flow wiring exists | `rg -n "fileImporter|onDrop|batchUseCase\\.convert|outputInboxStore\\.addItem|NSItemProvider\\(contentsOf:" Sources` | Expected matches in converter UI/use case/inbox | PASS |
| Commit scope included | `git show --name-only --oneline d05ffce 009bd52 f218131 74e5274` | Shows preset editor layout, converter UI, view model, and tests | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| CONV-01 | 03-03 | User can drag in or choose M4A and common audio files for conversion. | SATISFIED | `fileImporter`, `.onDrop`, scanner support, and intake tests. |
| CONV-02 | 03-01, 03-02, 03-03 | User can convert selected files to WAV PCM using the current project audio preset. | SATISFIED | Native and FFmpeg converters consume `ConversionRequest.preset`; full tests passed. |
| CONV-03 | 03-01, 03-03, 03-05 | User can choose or edit sample rate, bit depth, and channel handling for WAV output. | SATISFIED | `Edit WAV Preset` exposes menu pickers for supported sample rates, bit depths, and channel modes; edits persist to `AppSettings.audioPreset` and feed queued names plus conversion requests. |
| CONV-04 | 03-02, 03-03 | User can run batch conversions with per-file progress, success, and error states. | SATISFIED | Batch use case and view model expose converting/verified/failed/skipped states; tests passed. |
| CONV-05 | 03-01, 03-02, 03-03, 03-04 | App verifies output WAV metadata and records the result in the shared output inbox. | SATISFIED | `WAVOutputVerifier` gates converter success; `BatchAudioConversionUseCase` writes verified metadata to inbox. |
| UX-01 | 03-04 | User can reveal any output item in Finder. | SATISFIED programmatically; human smoke pending | Converter rows and inbox rows call `revealInFinder` for eligible existing WAVs. |
| UX-02 | 03-04 | User can drag generated files from the app or output inbox into Cubase/Finder-compatible targets. | SATISFIED programmatically; human smoke pending | `NSItemProvider(contentsOf:)` uses verified output URLs from converter rows and inbox rows. |

No additional Phase 3 requirement IDs were orphaned in `.planning/REQUIREMENTS.md`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift` | 36 | `onAppear`-only refresh | WARNING | Conversions write the store, but the always-present inspector may not show new items until recreated. |
| `Sources/AppCore/OutputInbox/OutputHandoff.swift` | 28 | Eligibility trusts status + extension + existence | WARNING | A stale or replaced available `.wav` can be revealed/dragged without re-verifying metadata. |
| `Tests/AppCoreTests/ExternalProcessRunningTests.swift` | 48 | Source-text security assertion | WARNING | Passing source scans are brittle; behavior tests cover more, but some UI/security checks still inspect text. |
| `Tests/FeatureAudioConverterTests/AudioConverterViewModelTests.swift` | 242 | Source-text UI copy/control assertions | WARNING | Useful as a guardrail, but not a substitute for running-app UI behavior. |

Empty-array returns found in `BatchAudioConversionUseCase` and `AudioConverterViewModel` are valid empty-input paths, not stubs.

### Human Verification Required

All automated must-haves now pass. These checks remain required before treating the phase as production-ready in the real app.

### 1. Running App Conversion Flow

**Test:** Launch `OutsideCubaseHub`, select `WAV Converter`, choose/drop real M4A, MP3, WAV, AIFF, and FLAC files, run a batch, trigger a missing-FFmpeg recovery row if possible, and use `Stop After Current File`.  
**Expected:** Supported files become rows, unsupported files show row errors, native-convertible files continue when FFmpeg is missing, progress and final row states match the batch, and verified outputs are created.  
**Why human:** Native file dialogs, drag/drop providers, and real file handling need running-app verification.

### 2. Finder/Cubase Drag Smoke

**Test:** Convert a short file, then drag from a verified converter row into Finder and Cubase; also drag from the shared output inbox.  
**Expected:** The dragged payload is the verified output WAV file URL and imports/lands as a file, not source metadata or a temp path. Failed/skipped/unverified rows are not draggable.  
**Why human:** Cross-app drag behavior cannot be fully proven by source inspection.

### 3. Output Inbox Live Appearance

**Test:** With the inspector visible, complete a conversion and watch whether the new output appears without reopening/recreating the view.  
**Expected:** The shared output inbox shows the newly converted item with metadata, reveal, and drag affordances.  
**Why human:** Source indicates `onAppear`-only refresh, so the current UI likely needs a reactive refresh path; running-app behavior should confirm impact.

### Gaps Summary

No automated gap remains after 03-05. The shared conversion pipeline is implemented and tested: native and FFmpeg conversion paths create verified WAVs, batch state is wired, successful outputs are persisted with metadata, reveal/drag code paths exist, and users can now edit WAV sample rate, bit depth, and channel handling from the production converter UI. Human smoke checks remain for native file dialogs, Finder/Cubase drag behavior, and live output inbox appearance.

---

_Verified: 2026-05-06T17:10:25Z_  
_Verifier: the agent (gsd-verifier)_
