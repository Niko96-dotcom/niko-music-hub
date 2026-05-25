---
phase: 01-app-foundation-and-tool-architecture
plan: "01"
subsystem: foundation
tags: [swift, swiftui, spm, appcore, registry]
requires: []
provides:
  - Native SwiftUI macOS executable target named OutsideCubaseHub
  - AppCore feature metadata, capability, registry, and context scaffold
  - Compact registry-driven shell with Dev Tool and secondary Output Inbox
affects: [phase-01, phase-02, feature-registration, app-shell]
tech-stack:
  added: [SwiftPM, SwiftUI, XCTest]
  patterns: [static composition root, registry-driven navigation, AppCore contracts]
key-files:
  created:
    - .gitignore
    - Package.swift
    - Sources/AppCore/Features/ToolFeature.swift
    - Sources/AppCore/Features/ToolRegistry.swift
    - Sources/AppCore/Services/ToolContext.swift
    - Sources/OutsideCubaseHub/OutsideCubaseHubApp.swift
    - Sources/OutsideCubaseHub/AppComposition.swift
    - Sources/OutsideCubaseHub/AppShell/AppShellView.swift
    - Sources/OutsideCubaseHub/AppShell/ToolSidebarView.swift
    - Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift
    - Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift
    - Tests/AppCoreTests/AppCoreSmokeTests.swift
  modified: []
key-decisions:
  - "Use SwiftPM as the first native macOS project structure so AppCore contracts are testable immediately."
  - "Keep Phase 1 navigation registry-driven and show only the registered Dev Tool."
patterns-established:
  - "AppComposition owns static startup registration."
  - "ToolRegistry preserves ordered ToolFeature metadata for sidebar selection."
requirements-completed: ["FND-01", "FND-02"]
duration: 8 min
completed: 2026-05-04
---

# Phase 01 Plan 01: App Scaffold and Navigation Shell Summary

**Native SwiftUI shell with AppCore registry contracts, a static Dev Tool registration, and launch-selection smoke coverage**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-04T10:12:30Z
- **Completed:** 2026-05-04T10:20:43Z
- **Tasks:** 3
- **Files modified:** 11

## Accomplishments

- Created the Swift Package Manager project with `AppCore`, `OutsideCubaseHub`, and `AppCoreTests`.
- Added the first feature contracts: `ToolFeatureID`, `ToolCapability`, `ToolMetadata`, `ToolFeature`, `ToolRegistry`, and `ToolContext`.
- Built a native SwiftUI `NavigationSplitView` shell that opens into the first registered tool and keeps `Output Inbox` secondary.
- Registered only `Dev Tool` through `AppComposition`, with no disabled future BPM, conversion, recorder, downloader, FFmpeg, or yt-dlp UI.
- Added AppCore smoke tests for metadata ordering and first-feature launch selection.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Swift package and minimal AppCore contracts** - `cbbb1d3` (feat)
2. **Task 2: Build native shell, startup composition, and registered Dev Tool** - `aa17ca3` (feat)
3. **Task 3: Add scaffold smoke coverage and launch verification notes** - `8628fab` (test)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `.gitignore` - Keeps SwiftPM and Xcode generated build products out of version control.
- `Package.swift` - SwiftPM scaffold with macOS 14.2 deployment, AppCore library, app executable, and tests.
- `Sources/AppCore/Features/ToolFeature.swift` - Feature IDs, metadata, capability flags, and base feature protocol.
- `Sources/AppCore/Features/ToolRegistry.swift` - Ordered feature registry and first-launch selection helper.
- `Sources/AppCore/Services/ToolContext.swift` - Initial shared context value for registered tool diagnostics.
- `Sources/OutsideCubaseHub/OutsideCubaseHubApp.swift` - SwiftUI `@main` entrypoint.
- `Sources/OutsideCubaseHub/AppComposition.swift` - Static startup composition root registering `DevToolFeature()`.
- `Sources/OutsideCubaseHub/AppShell/AppShellView.swift` - Compact `NavigationSplitView` shell with minimum 900 by 600 window sizing.
- `Sources/OutsideCubaseHub/AppShell/ToolSidebarView.swift` - Sidebar rows rendered from `registry.features`.
- `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift` - Secondary output inbox surface with approved empty copy.
- `Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift` - Registered Dev Tool metadata and foundation diagnostics view.
- `Tests/AppCoreTests/AppCoreSmokeTests.swift` - XCTest smoke coverage for registry ordering and launch selection.

## Decisions Made

- Used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for Swift gates because the active CommandLineTools developer directory does not expose `XCTest`.
- Kept the Dev Tool capability set empty in this scaffold so it does not imply real file production or job execution before Plans 01-02 and 01-03 add those shared services.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] PackageDescription lacks `.v14_2` on the active manifest API**
- **Found during:** Task 1 (Create Swift package and minimal AppCore contracts)
- **Issue:** `Package.swift` failed to compile with `.macOS(.v14_2)` because this installed PackageDescription API exposes major-version constants but not the 14.2 patch constant.
- **Fix:** Used `.macOS("14.2")` with a short manifest comment noting it is equivalent to `macOS(.v14_2)` for this toolchain.
- **Files modified:** `Package.swift`
- **Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed.
- **Committed in:** `cbbb1d3`

**2. [Rule 3 - Blocking] SwiftPM generated untracked build output**
- **Found during:** Plan metadata commit
- **Issue:** Running `swift test` created `.build/`, which would remain as untracked generated output during subsequent GSD waves.
- **Fix:** Added `.gitignore` entries for `.build/`, `.swiftpm/`, and `DerivedData/`.
- **Files modified:** `.gitignore`, `.planning/phases/01-app-foundation-and-tool-architecture/01-01-SUMMARY.md`
- **Verification:** `git status --short --ignored` shows `.build/` ignored.
- **Committed in:** this summary hygiene commit

---

**Total deviations:** 2 auto-fixed (Rule 3 blocking). **Impact on plan:** Deployment target remains macOS 14.2, the package compiles on the installed toolchain, and generated build output is ignored.

## Issues Encountered

- `swift test` under `/Library/Developer/CommandLineTools` failed with `no such module 'XCTest'`; rerunning the same Swift test gate with Xcode.app via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` passed.

## User Setup Required

None - no external service configuration required.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed.
- `rg -n "BPM|Converter|Recorder|Downloader|yt-dlp|FFmpeg" Sources/OutsideCubaseHub` returned no matches.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run OutsideCubaseHub` launch smoke stayed alive for 3 seconds before being stopped by the executor.

## Next Phase Readiness

Ready for Plan 01-02. The app scaffold, AppCore module, static composition root, and registered Dev Tool exist for the feature-boundary hardening work.

---
*Phase: 01-app-foundation-and-tool-architecture*
*Completed: 2026-05-04*
