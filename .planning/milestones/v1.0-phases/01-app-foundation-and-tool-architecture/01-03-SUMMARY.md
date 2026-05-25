---
phase: 01-app-foundation-and-tool-architecture
plan: "03"
subsystem: foundation
tags: [swift, settings, output-inbox, jobs, persistence, file-actions]
requires:
  - phase: 01-app-foundation-and-tool-architecture
    provides: ToolContext service protocol boundary and registry-driven shell
provides:
  - Persisted AppSettings with output folder, audio preset defaults, and helper paths
  - Durable JSON output inbox metadata store
  - Shared async JobRunner with queued/running/completed/failed/canceled states
affects: [phase-02, phase-03, phase-04, phase-05, output-handoff, shared-jobs]
tech-stack:
  added: [UserDefaults, JSONEncoder, JSONDecoder, NSOpenPanel, NSWorkspace]
  patterns: [local settings store, atomic JSON metadata store, shared async job runner]
key-files:
  created:
    - Sources/AppCore/Settings/AppSettings.swift
    - Sources/AppCore/Settings/AudioPreset.swift
    - Sources/AppCore/Settings/HelperToolSettings.swift
    - Sources/AppCore/Settings/UserDefaultsSettingsStore.swift
    - Sources/AppCore/OutputInbox/OutputInboxItem.swift
    - Sources/AppCore/OutputInbox/JSONOutputInboxStore.swift
    - Sources/AppCore/Jobs/Job.swift
    - Sources/AppCore/Jobs/JobRunner.swift
    - Sources/AppCore/Files/FileActions.swift
    - Sources/AppCore/Diagnostics/Diagnostics.swift
    - Tests/AppCoreTests/SettingsStoreTests.swift
    - Tests/AppCoreTests/OutputInboxStoreTests.swift
    - Tests/AppCoreTests/JobRunnerTests.swift
  modified:
    - Sources/AppCore/Services/SettingsStore.swift
    - Sources/AppCore/Services/OutputInboxStore.swift
    - Sources/AppCore/Services/JobRunning.swift
    - Sources/OutsideCubaseHub/AppComposition.swift
    - Sources/OutsideCubaseHub/AppShell/AppShellView.swift
    - Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift
    - Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift
    - Tests/AppCoreTests/AppCoreSmokeTests.swift
    - Tests/AppCoreTests/ToolContextTests.swift
key-decisions:
  - "Persist helper paths as optional local URLs only; do not execute helper tools in Phase 1."
  - "Use JSON output inbox metadata with atomic writes behind OutputInboxStore."
  - "Use one shared JobRunner state machine for later conversion, recording, and download work."
patterns-established:
  - "UserDefaultsSettingsStore provides local settings persistence with isolated test suites."
  - "OutputInboxInspectorView reads OutputInboxItem records from ToolContext without becoming the active tool."
  - "Dev Tool sample jobs run through the shared job runner only."
requirements-completed: ["FND-03", "FND-04", "FND-05"]
duration: 12 min
completed: 2026-05-04
---

# Phase 01 Plan 03: Output Inbox, Settings, and Job Primitives Summary

**Persisted output settings, durable output inbox records, and a shared async job runner wired into the Phase 1 shell**

## Performance

- **Duration:** 12 min
- **Started:** 2026-05-04T10:22:30Z
- **Completed:** 2026-05-04T10:34:36Z
- **Tasks:** 3
- **Files modified:** 22

## Accomplishments

- Added `AppSettings`, `AudioPreset`, `HelperToolSettings`, `StoredFolderLocation`, and `UserDefaultsSettingsStore`.
- Defaulted the output folder to `~/Music/Outside Cubase Hub/Inbox` and persisted output folder, audio preset, and helper paths.
- Added `OutputInboxItem` with file URL, source tool, created date, status, and metadata, plus `JSONOutputInboxStore` with atomic writes and missing-file refresh.
- Added `Job`, `JobState`, `JobLogEntry`, `JobProgress`, and `JobRunner` covering queued, running, completed, failed, and canceled states.
- Wired `AppComposition` to real settings, output inbox, job runner, AppKit file actions, and diagnostics adapters.
- Updated `OutputInboxInspectorView` to list stored records and `DevToolFeature` to choose output folders and run/stop sample jobs through shared services.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement persisted settings and audio/helper defaults** - `4880203` (feat)
2. **Task 2: Implement durable output inbox model and inspector integration** - `60e28ca` (test)
3. **Task 3: Implement shared job model, runner, sample job surface, and tests** - `a4c1a60` (test)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Sources/AppCore/Settings/AppSettings.swift` - App settings and stored output folder location.
- `Sources/AppCore/Settings/AudioPreset.swift` - Cubase-ready default audio preset: 48 kHz, 24-bit, 2-channel stereo.
- `Sources/AppCore/Settings/HelperToolSettings.swift` - Optional helper paths for `ffmpeg`, `ffprobe`, and `ytDlp`.
- `Sources/AppCore/Settings/UserDefaultsSettingsStore.swift` - Local UserDefaults settings persistence.
- `Sources/AppCore/OutputInbox/OutputInboxItem.swift` - Durable output metadata item and statuses.
- `Sources/AppCore/OutputInbox/JSONOutputInboxStore.swift` - JSON output inbox store with atomic writes and availability refresh.
- `Sources/AppCore/Jobs/Job.swift` - Shared job model, states, progress, messages, logs, and timestamps.
- `Sources/AppCore/Jobs/JobRunner.swift` - Async in-memory runner with cancellation.
- `Sources/AppCore/Files/FileActions.swift` - File chooser and Finder reveal action boundary.
- `Sources/AppCore/Diagnostics/Diagnostics.swift` - Diagnostic protocol and console implementation.
- `Sources/OutsideCubaseHub/AppComposition.swift` - Injects persisted settings, JSON output inbox, JobRunner, AppKit file actions, and diagnostics.
- `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift` - Lists output records and exposes `Reveal in Finder` only for available files.
- `Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift` - Runs `Run Sample Job`, exposes `Stop Job`, and updates output folder settings.
- `Tests/AppCoreTests/SettingsStoreTests.swift` - Settings persistence tests.
- `Tests/AppCoreTests/OutputInboxStoreTests.swift` - Output inbox persistence and missing-file tests.
- `Tests/AppCoreTests/JobRunnerTests.swift` - Job state, progress, message, log, failure, and cancellation tests.

## Decisions Made

- Kept settings and output metadata local and testable with injected `UserDefaults` suites and temporary JSON store URLs.
- Marked the concrete Foundation-backed stores as `@unchecked Sendable` while keeping the protocols Sendable, because `UserDefaults` and `FileManager` are Foundation reference types used synchronously inside small adapters.
- Moved the temporary Plan 01-02 service placeholder types into final `Settings`, `OutputInbox`, `Jobs`, `Files`, and `Diagnostics` folders as part of the first Plan 01-03 task so the package remained compilable while models were promoted.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Swift 6 Sendable checks on Foundation adapters**
- **Found during:** Task 1 (Implement persisted settings and audio/helper defaults)
- **Issue:** `UserDefaultsSettingsStore` and `JSONOutputInboxStore` conformed to Sendable protocols but stored `UserDefaults` and `FileManager`, which are not declared Sendable by Foundation.
- **Fix:** Marked the concrete adapters as `@unchecked Sendable` and kept their operations synchronous and narrow.
- **Files modified:** `Sources/AppCore/Settings/UserDefaultsSettingsStore.swift`, `Sources/AppCore/OutputInbox/JSONOutputInboxStore.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SettingsStoreTests` passed.
- **Committed in:** `4880203`

---

**Total deviations:** 1 auto-fixed (Rule 3 blocking). **Impact on plan:** No behavior scope change; strict concurrency now accepts the concrete local adapters.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SettingsStoreTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OutputInboxStoreTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter JobRunnerTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 19 XCTest cases.
- Source scan found no Core Audio capture, helper execution, recorder, converter, downloader, or BPM tool behavior introduced in Phase 1.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run OutsideCubaseHub` launch smoke stayed alive for 3 seconds before being stopped by the executor.

## Next Phase Readiness

Phase 1 foundations are ready for verification. Phase 2 can register a real BPM tool through the feature boundary and reuse the shared settings, output inbox, diagnostics, file actions, and job primitives.

---
*Phase: 01-app-foundation-and-tool-architecture*
*Completed: 2026-05-04*
