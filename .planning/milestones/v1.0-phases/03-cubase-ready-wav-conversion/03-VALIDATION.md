---
phase: 03
slug: cubase-ready-wav-conversion
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-05
---

# Phase 03 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via Swift Package Manager |
| **Config file** | `Package.swift` |
| **Quick run command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureAudioConverterTests` |
| **Full suite command** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` |
| **Estimated runtime** | ~10-45 seconds |

## Sampling Rate

- **After every task commit:** Run the focused test command for the touched target. Prefer `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureAudioConverterTests` once the target exists.
- **After every plan wave:** Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- **Before `$gsd-verify-work`:** Full suite must be green.
- **Max feedback latency:** 45 seconds for focused tests, 90 seconds for full suite.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | CONV-02, CONV-03 | T-03-PRESET | Preset/channel policy is explicit and preserves mono/stereo by default. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioPresetTests` | W0 | pending |
| 03-01-02 | 01 | 1 | CONV-02, CONV-05 | T-03-WAVSPEC | Native outputs are temp-written, moved only after WAV metadata verification, and source files remain untouched. | unit + integration | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NativeAudioConverterTests` | W0 | pending |
| 03-02-01 | 02 | 2 | CONV-02, CONV-05 | T-03-PROCESS | FFmpeg fallback uses executable URL plus argv array; no shell interpolation. | unit + source scan | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FFmpegAudioConverterTests` | W0 | pending |
| 03-02-02 | 02 | 2 | CONV-04 | T-03-HELPER | Missing FFmpeg fails only fallback-required rows with recovery guidance. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FFmpegHealthTests` | W0 | pending |
| 03-03-01 | 03 | 3 | CONV-01, CONV-04 | T-03-BATCH | Drag/choose intake accepts only supported top-level files and keeps mixed row states recoverable. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioConverterViewModelTests` | W0 | pending |
| 03-03-02 | 03 | 3 | CONV-05 | T-03-INBOX | Output inbox records only verified WAVs with source/spec/converter metadata. | unit | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BatchAudioConversionUseCaseTests` | W0 | pending |
| 03-04-01 | 04 | 4 | UX-01, UX-02 | T-03-HANDOFF | Reveal and drag-out are available only for existing verified WAV outputs. | unit + source scan + manual | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputHandoffTests` | W0 | pending |

## Wave 0 Requirements

Existing infrastructure covers the phase:

- `Package.swift` already defines SwiftPM targets and XCTest.
- `AppCoreTests` and `FeatureBPMTapperTests` run through SwiftPM.
- Phase 3 should add `FeatureAudioConverterTests` before or alongside the converter target.
- No watch-mode or long-running harness is needed.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real M4A/MP3/WAV/AIFF/FLAC files can be dropped or chosen in the running app. | CONV-01 | Native file dialogs and drag providers are best verified in the app. | Launch `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run OutsideCubaseHub`, select WAV Converter, drop or choose one file of each supported type, and confirm supported rows appear while unsupported files get inline row errors. |
| Converted WAV imports into a Cubase/Finder-compatible target by drag-out. | UX-02 | Requires real AppKit drag destination behavior. | Convert a short audio file, drag the verified WAV row into Finder or Cubase, and confirm the destination receives the WAV file URL. |
| Reveal opens Finder for converter rows and output inbox rows. | UX-01 | Uses NSWorkspace/AppKit behavior. | Convert a file, click `Reveal in Finder` from both the converter result row and the output inbox row, and confirm Finder selects the same WAV. |
| FFmpeg fallback works with the locally configured helper. | CONV-02, CONV-04 | Depends on local helper path and real codecs. | Configure `/opt/homebrew/bin/ffmpeg` if needed, convert a file that native conversion rejects, and confirm only that row uses converter `FFmpeg`. |

## Validation Sign-Off

- [x] All tasks have automated verify commands or manual smoke instructions.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency under 90 seconds.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** draft 2026-05-05
