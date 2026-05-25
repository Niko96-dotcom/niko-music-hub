---
phase: 03-cubase-ready-wav-conversion
plan: "04"
subsystem: output-handoff-ui
tags: [swift, swiftui, macos, drag-and-drop, output-inbox, xctest]
requires:
  - phase: 03-cubase-ready-wav-conversion
    provides: verified WAV conversion rows and output inbox writes from 03-03
provides:
  - Shared OutputHandoff readiness rules for reveal and drag-out
  - Output inbox reveal and drag providers gated to available existing WAV files
  - Converter row reveal and Drag WAV to Cubase affordances gated to verified existing WAV files
  - Source-scan and behavior tests covering failed, skipped, missing, non-WAV, and verified WAV handoff states
affects: [phase-04-recorder-output-handoff, output-inbox, audio-converter-ui]
tech-stack:
  added: []
  patterns: [shared handoff eligibility helper, NSItemProvider file URL drag providers, source-scan UI contract tests]
key-files:
  created:
    - Sources/AppCore/OutputInbox/OutputHandoff.swift
    - Tests/AppCoreTests/OutputHandoffTests.swift
    - Tests/FeatureAudioConverterTests/AudioConverterHandoffTests.swift
  modified:
    - Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift
    - Sources/FeatureAudioConverter/AudioConverterView.swift
    - Sources/FeatureAudioConverter/AudioConverterViewModel.swift
    - Tests/AppCoreTests/OutputInboxStoreTests.swift
key-decisions:
  - "Reveal and drag readiness are both gated by OutputHandoff, which only accepts .available existing .wav files."
  - "Converter rows reuse the shared output handoff policy by mapping verified row output URLs through OutputHandoff before exposing NSItemProvider."
  - "Drag providers expose only verified WAV file URLs; failed, skipped, missing, pending, unsupported, non-WAV, source, and metadata values do not become payloads."
patterns-established:
  - "Shared output handoff policy belongs in AppCore so future file-producing tools can reuse the same safety gate."
  - "Executable-target SwiftUI handoff wiring is protected with source-scan tests from library test targets."
requirements-completed: ["CONV-05", "UX-01", "UX-02"]
duration: 6 min
completed: 2026-05-05
---

# Phase 03 Plan 04: Verified Output Handoff Summary

**Verified WAV handoff now uses one shared readiness gate for Finder reveal and drag-out from both converter rows and the shared output inbox**

## Performance

- **Duration:** 6 min
- **Started:** 2026-05-05T08:04:32Z
- **Completed:** 2026-05-05T08:10:44Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- Added `OutputHandoff` in `AppCore` so reveal and drag readiness require `.available`, an existing file, and a `.wav` extension.
- Updated the shared output inbox inspector to show `Reveal in Finder`, converter metadata, and `NSItemProvider(contentsOf:)` drag-out only for verified WAV outputs.
- Updated converter result rows to expose `Reveal in Finder` and `Drag WAV to Cubase` only when `row.verifiedOutputURLForDrag()` returns an existing WAV file URL.
- Added focused tests and source scans for both surfaces, including failed, skipped, missing, non-WAV, and verified-ready cases.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add shared output handoff eligibility helper** - `3280109` (feat)
2. **Task 2: Add reveal and drag-out to the shared output inbox** - `034887c` (feat)
3. **Task 3: Add reveal and drag-out to verified converter result rows** - `6d7d0a6` (feat)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Sources/AppCore/OutputInbox/OutputHandoff.swift` - Shared reveal/drag eligibility and drag URL helper for available existing WAV outputs.
- `Tests/AppCoreTests/OutputHandoffTests.swift` - Covers available existing WAV, missing file, failed item, and non-WAV item readiness.
- `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift` - Adds OutputHandoff-gated reveal and drag-out plus converter metadata lines.
- `Tests/AppCoreTests/OutputInboxStoreTests.swift` - Adds source scan coverage for output inbox handoff wiring.
- `Sources/FeatureAudioConverter/AudioConverterViewModel.swift` - Adds row-level `isDragReady` and `verifiedOutputURLForDrag` helpers.
- `Sources/FeatureAudioConverter/AudioConverterView.swift` - Adds gated converter row drag provider, reveal action, and `Drag WAV to Cubase` affordance.
- `Tests/FeatureAudioConverterTests/AudioConverterHandoffTests.swift` - Covers converter row handoff readiness and source scans.

## Decisions Made

- Used `OutputHandoff` as the single readiness policy for both reveal and drag. This keeps recorder outputs in Phase 4 from needing a second handoff rule.
- Kept drag providers file-only with `NSItemProvider(contentsOf:)`. No source URLs, temp URLs, metadata strings, failed rows, skipped rows, or unsupported rows are exposed as drag payloads.
- Added source-scan assertions for executable-target SwiftUI files because the existing test targets do not import the executable target directly.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Manual smoke verification was not run in this non-interactive executor. Automated tests and source scans passed; real Finder/Cubase drag behavior remains best verified in the running macOS app.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputHandoffTests` passed with 4 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioConverterHandoffTests` passed with 5 tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 95 tests.
- `rg -n "NSItemProvider\\(contentsOf:|OutputHandoff\\.dragFileURL|Drag WAV to Cubase|revealInFinder" Sources/AppCore Sources/OutsideCubaseHub Sources/FeatureAudioConverter` returned matches in both UI surfaces and shared handoff paths.

## User Setup Required

None - no external service configuration required.

## Auth Gates

None.

## Known Stubs

None - stub scan found only legitimate empty collection initializers and optional defaults for local view-model state. No placeholder/TODO/FIXME copy or disconnected handoff UI data source was introduced.

## Next Phase Readiness

Phase 4 recorder work can reuse `OutputHandoff` for recorder-created WAVs and the shared output inbox can already reveal and drag available verified WAV outputs.

## Self-Check: PASSED

- Summary file exists.
- Key created files exist: `OutputHandoff.swift`, `OutputHandoffTests.swift`, and `AudioConverterHandoffTests.swift`.
- Task commits exist: `3280109`, `034887c`, and `6d7d0a6`.

---
*Phase: 03-cubase-ready-wav-conversion*
*Completed: 2026-05-05*
