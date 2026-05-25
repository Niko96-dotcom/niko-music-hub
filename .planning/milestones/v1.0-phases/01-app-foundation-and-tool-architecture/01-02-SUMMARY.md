---
phase: 01-app-foundation-and-tool-architecture
plan: "02"
subsystem: foundation
tags: [swift, swiftui, appcore, registry, toolcontext, services]
requires:
  - phase: 01-app-foundation-and-tool-architecture
    provides: Native SwiftUI scaffold and initial AppCore feature contracts
provides:
  - ToolFeature view factory boundary using ToolContext
  - Duplicate-safe immutable ToolRegistry with lookup and ordered metadata
  - Shared service protocols carried by ToolContext
affects: [phase-01, phase-02, feature-registration, settings, output-inbox, jobs]
tech-stack:
  added: []
  patterns: [ToolFeature view factory, duplicate-safe registry, service-injected ToolContext]
key-files:
  created:
    - Sources/AppCore/Services/SettingsStore.swift
    - Sources/AppCore/Services/OutputInboxStore.swift
    - Sources/AppCore/Services/JobRunning.swift
    - Sources/AppCore/Services/FileActions.swift
    - Sources/AppCore/Services/Diagnostics.swift
    - Tests/AppCoreTests/FeatureRegistryTests.swift
    - Tests/AppCoreTests/ToolContextTests.swift
  modified:
    - Sources/AppCore/Features/ToolFeature.swift
    - Sources/AppCore/Features/ToolRegistry.swift
    - Sources/AppCore/Services/ToolContext.swift
    - Sources/OutsideCubaseHub/AppComposition.swift
    - Sources/OutsideCubaseHub/AppShell/AppShellView.swift
    - Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift
    - Tests/AppCoreTests/AppCoreSmokeTests.swift
key-decisions:
  - "ToolFeature owns SwiftUI view creation through a MainActor AnyView factory."
  - "ToolRegistry construction throws on duplicate IDs instead of silently accepting ambiguous navigation."
  - "ToolContext carries protocol dependencies so future tools do not reach into shell internals."
patterns-established:
  - "Features expose metadata plus makeView(context:) and are rendered by the shell through that boundary."
  - "AppComposition remains the production registration site and injects temporary preview services."
requirements-completed: ["FND-02"]
duration: 5 min
completed: 2026-05-04
---

# Phase 01 Plan 02: Feature Registry and Tool Context Summary

**ToolFeature view factories, duplicate-safe registry validation, and shared ToolContext service injection**

## Performance

- **Duration:** 5 min
- **Started:** 2026-05-04T10:21:20Z
- **Completed:** 2026-05-04T10:26:17Z
- **Tasks:** 3
- **Files modified:** 14

## Accomplishments

- Added `@MainActor func makeView(context: ToolContext) -> AnyView` to `ToolFeature` and routed `AppShellView` through feature-owned views.
- Made `ToolRegistry` immutable, ordered, lookupable, and duplicate-safe with deterministic `DuplicateToolFeatureID` errors.
- Added `SettingsStore`, `OutputInboxStore`, `JobRunning`, `FileActions`, and `Diagnostics` protocols to the AppCore service boundary.
- Updated `ToolContext` to carry injected shared services and wired local preview implementations in `AppComposition`.
- Added focused XCTest coverage for registration order, lookup, capability flags, duplicate rejection, second-feature addition, and ToolContext injection.

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand feature metadata, capability flags, and view factory** - `439c12a` (feat)
2. **Task 2: Make registry immutable, ordered, lookupable, and duplicate-safe** - `f5f37ed` (feat)
3. **Task 3: Define shared ToolContext service protocols and composition wiring** - `0719ef4` (feat)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `Sources/AppCore/Features/ToolFeature.swift` - Adds MainActor view factory to the feature boundary.
- `Sources/AppCore/Features/ToolRegistry.swift` - Adds ordered metadata storage, lookup, and duplicate-id validation.
- `Sources/AppCore/Services/ToolContext.swift` - Carries injected service protocols for features.
- `Sources/AppCore/Services/SettingsStore.swift` - Defines settings protocol and minimal `AppSettings`.
- `Sources/AppCore/Services/OutputInboxStore.swift` - Defines output inbox protocol and minimal item model.
- `Sources/AppCore/Services/JobRunning.swift` - Defines job protocol and minimal job model.
- `Sources/AppCore/Services/FileActions.swift` - Defines file choosing and Finder reveal actions.
- `Sources/AppCore/Services/Diagnostics.swift` - Defines diagnostic levels and logging protocol.
- `Sources/OutsideCubaseHub/AppComposition.swift` - Keeps static registration and injects temporary preview services.
- `Sources/OutsideCubaseHub/AppShell/AppShellView.swift` - Renders selected features through `makeView(context:)`.
- `Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift` - Implements the feature view factory and displays service-backed foundation diagnostics.
- `Tests/AppCoreTests/FeatureRegistryTests.swift` - Registry behavior tests.
- `Tests/AppCoreTests/ToolContextTests.swift` - ToolContext injection and view factory tests.
- `Tests/AppCoreTests/AppCoreSmokeTests.swift` - Updated smoke fixtures for throwing registry init and view factory protocol conformance.

## Decisions Made

- Used a throwing `ToolRegistry(features:)` initializer so duplicate IDs cannot silently reach the shell.
- Kept Plan 01-02 service models intentionally minimal in `Sources/AppCore/Services/*`; Plan 01-03 is ready to move and expand them into durable settings, output inbox, and job modules.

## Deviations from Plan

None - plan executed exactly as written.

---

**Total deviations:** 0 auto-fixed. **Impact on plan:** No scope change.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureRegistryTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ToolContextTests` passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed.
- Source scan found no global mutable registry or self-registration API; `AppComposition` remains the only production startup registration site.

## Next Phase Readiness

Ready for Plan 01-03. Future tools now have a tested feature boundary and service-injected context for durable settings, output records, file actions, diagnostics, and jobs.

---
*Phase: 01-app-foundation-and-tool-architecture*
*Completed: 2026-05-04*
