# Phase 1 Research: App Foundation and Tool Architecture

**Phase:** 01 - App Foundation and Tool Architecture
**Researched:** 2026-05-04T11:54:27+02:00
**Status:** Ready for UI design contract, then planning
**Question:** What do I need to know to plan this phase well?

## Executive Summary

Phase 1 should create the first real native macOS app structure, not a disposable prototype. The smallest useful foundation is a Swift/SwiftUI app shell backed by a testable AppCore package: feature registration, shared tool context, settings persistence, output inbox metadata, and job primitives. No BPM, conversion, recording, or downloader behavior should appear yet except as contracts that later phases can use.

The highest-value planning move is to make extension pressure visible immediately: register one dummy/dev feature through the same feature boundary future tools will use, open into that first registered tool, and prove with tests that a second feature can be added without editing existing feature internals.

## Starting Point

- No app source exists yet. Phase 1 will create the first `Package.swift`, `Sources/`, and `Tests/` structure.
- Swift 6.3 is installed locally, targeting arm64 macOS.
- FFmpeg 8.1 and yt-dlp 2026.03.17 are available for later development, but Phase 1 should only persist helper path settings and not invoke either helper.
- The phase already has locked discuss-phase decisions in `01-CONTEXT.md`; planning must keep D-01 through D-16 visible in plan `must_haves`, task actions, or truth statements.

## Architecture Findings

### App Scaffold

Use a Swift Package Manager layout first because it keeps module boundaries and tests simple from the first commit. The executable target can host a SwiftUI `@main` macOS app:

```text
Package.swift
Sources/
  OutsideCubaseHub/
    OutsideCubaseHubApp.swift
    AppComposition.swift
    AppShell/
    DevTool/
  AppCore/
    Features/
    Settings/
    OutputInbox/
    Jobs/
    Files/
    Diagnostics/
Tests/
  AppCoreTests/
```

The app target should depend on `AppCore`; later feature packages can also depend on `AppCore` without knowing shell internals. If distribution later requires a richer app bundle or notarization flow, an Xcode project can wrap the same package targets rather than forcing a rewrite.

### Feature Registry

Plan a small explicit registration model:

- `ToolFeatureID`: stable string-backed identifier.
- `ToolCapability`: option set or struct with at least `producesFiles` and `runsJobs`.
- `ToolMetadata`: id, display name, short label, optional system image, capability flags.
- `ToolFeature`: protocol exposing metadata and a `@MainActor` view factory.
- `ToolRegistry`: immutable collection with lookup, ordering, and duplicate-id validation.
- `ToolContext`: shared services passed into feature view factories.

Registration should happen in a static composition root such as `AppComposition.makeToolRegistry(context:)`. Avoid global mutable registries and automatic self-registration in Phase 1; those make ordering, testing, and future feature isolation harder.

### Shell And Navigation

The shell should be compact and work-focused:

- Sidebar or tool list primary navigation.
- Active tool view takes the main space.
- Output inbox is always reachable but secondary, likely as a trailing inspector, bottom drawer, toolbar button, or split panel depending on the UI contract.
- Launch selection is the first registered tool.
- Phase 1 shows only the dummy/dev feature. Do not show disabled BPM/converter/recorder/downloader placeholders.

Because this phase has explicit UI scope, `01-UI-SPEC.md` should be generated before PLAN.md files are finalized. The plan should treat UI-SPEC as the visual and interaction contract.

### Tool Context And Shared Services

`ToolContext` should carry service protocols, not concrete singletons:

- `settingsStore`: persists app settings and audio preset defaults.
- `outputInboxStore`: records generated output items and metadata.
- `jobRunner` or `jobStore`: creates and tracks shared jobs.
- `fileActions`: reveal/open/select folder actions, with AppKit implementation in the app target.
- `diagnostics`: structured logging surface, backed later by OSLog.

The app shell owns concrete service construction. Feature modules receive context and remain replaceable.

### Settings Persistence

Phase 1 settings should include:

- `outputFolder`: default to `~/Music/Outside Cubase Hub/Inbox`.
- `audioPreset`: sample rate, bit depth, and channel count/channel mode defaults for later WAV tools.
- `helperTools`: optional paths for `ffmpeg`, `ffprobe`, and `yt-dlp`.

Use a protocol such as `SettingsStore` with a simple local implementation. For an initial local non-App-Store app, `UserDefaults` is acceptable for scalar values and helper paths. For the output folder, prefer bookmark data or a resolved file URL wrapper so the app can evolve toward sandboxed file access later. Tests should use an isolated `UserDefaults(suiteName:)` or temp-backed fake store so persistence is deterministic.

### Output Inbox Model

Create a real model even before file-producing tools exist. Minimum fields:

- `id`
- `fileURL`
- `sourceToolID`
- `createdAt`
- `status`: at least pending, available, missing, failed
- `metadata`: string dictionary or typed extensible payload for later source URL/audio format details

Persist inbox metadata under Application Support or a temp-injectable store path. A JSON store is enough for v1 as long as writes are atomic and the storage API is behind `OutputInboxStore`. File reveal and drag-out behavior can be represented by contracts in Phase 1; deeper AppKit drag polish can wait for file-producing phases.

### Job Primitives

The shared job model should support all states named in FND-04:

- queued
- running
- completed
- failed
- canceled

Include `progress`, `message`, append-only log entries, timestamps, and a cancellation hook/token. The Phase 1 runner can be lightweight: enough to create jobs, transition state, run an async operation, record failure messages, and cancel before or during execution. Conversion, recording, and downloads should not need to invent separate state machines later.

## Suggested Plan Slices

### 01-01: App Scaffold And Navigation Shell

Create the SPM package, executable SwiftUI app, app composition root, compact shell layout, and dummy/dev feature view. This covers FND-01 and proves the native shell launches into a registered tool.

### 01-02: Feature Registry And Tool Context

Create AppCore feature contracts, registry validation, capability flags, tool context service protocols, and tests proving duplicate rejection and isolated feature addition. This covers FND-02 and D-01 through D-05.

### 01-03: Output Inbox, Settings, And Job Primitives

Create settings, output inbox, file action contracts, and job model/runner with tests for persistence and state transitions. This covers FND-03 through FND-05 and prepares later file-producing phases.

## Risk And Pitfall Notes

- Do not hard-code future tool cases into the sidebar. Use the registry even for the first dummy tool.
- Do not treat output folder persistence as a plain string forever. A URL/bookmark-shaped abstraction avoids future sandbox pain.
- Do not add FFmpeg or yt-dlp command execution in this phase. Persist helper paths only.
- Do not build a large dashboard. The UI should open into the active registered tool.
- Avoid one massive observable app model. Keep shell state, settings, inbox, and jobs behind smaller services.

## Validation Architecture

Use XCTest through Swift Package Manager from the first scaffold.

### Automated Coverage

- `swift test` must run once `Package.swift` exists.
- Feature registry tests cover ordering, lookup, capability flags, duplicate-id rejection, and adding a second dummy feature without modifying existing feature internals.
- Settings tests cover output folder persistence, audio preset defaults, and helper tool path persistence using an isolated test store.
- Output inbox tests cover add/list/update persistence with temp directories and missing-file state detection.
- Job tests cover queued, running, completed, failed, and canceled transitions plus progress/message/log updates.

### Manual Coverage

- Launch the app locally and confirm it opens into the first registered dummy/dev feature.
- Confirm navigation is sidebar/tool-list based and does not show disabled roadmap placeholders.
- Confirm the output inbox is reachable without becoming the primary screen.

### Feedback Sampling

- After the scaffold task: run `swift test` to verify the package and test target are wired.
- After registry/context work: run `swift test --filter AppCoreTests`.
- After settings/output/job work: run full `swift test`.
- Before execution verification: run full `swift test` and manually launch the app once.

## Research Complete

Phase 1 can be planned after a UI design contract exists. The technical plan should create three PLAN.md files matching the roadmap slices and must keep FND-01 through FND-05 plus decisions D-01 through D-16 traceable.
