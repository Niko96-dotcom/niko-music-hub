# Phase 1: App Foundation and Tool Architecture - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-04T11:49:56+02:00
**Phase:** 1-App Foundation and Tool Architecture
**Areas discussed:** Feature Registry Shape, Shell And Navigation Feel, Output Inbox, Settings, Jobs

---

## Feature Registry Shape

### Feature Boundary Strictness

| Option | Description | Selected |
|--------|-------------|----------|
| Strict module boundary | Each tool exposes metadata and a view factory through a `ToolFeature`-style protocol; shared services come through `ToolContext`. | |
| Lightweight registry first | Tools register title/icon/view only; deeper use-case/service boundaries can grow when BPM/conversion arrive. | |
| Agent decides | Lock the goal, leave exact protocol shape to planning. | ✓ |

**User's choice:** Agent decides.
**Notes:** Exact protocol shape remains flexible, but tools must register through a feature boundary and receive shared services through context.

### Future Tool Placeholders

| Option | Description | Selected |
|--------|-------------|----------|
| Only real registered tools | Show a dummy/dev feature for testing, but do not show BPM/converter/recorder/downloader until their phases implement them. | ✓ |
| Visible roadmap placeholders | Show disabled future tools so the hub shape is obvious from day one. | |
| Agent decides | Planner can pick whichever keeps the scaffold clean. | |

**User's choice:** Only real registered tools.
**Notes:** A dummy/dev feature is fine for proving registration.

### Registration Location

| Option | Description | Selected |
|--------|-------------|----------|
| Static composition root | App startup owns the list of registered features; feature modules do not mutate global state. | ✓ |
| Self-registering modules | Each feature announces itself automatically, which feels plug-in-like but adds more machinery early. | |
| Agent decides | Leave registration mechanics open as long as adding a tool stays isolated. | |

**User's choice:** Static composition root.
**Notes:** Keep registration simple and testable in Phase 1.

### Registry Metadata

| Option | Description | Selected |
|--------|-------------|----------|
| Metadata + view factory + capability flags | Title, icon, description, feature id, view factory, and whether it produces files or jobs. | ✓ |
| Metadata + view factory only | Keep it very small; later tools add capabilities when needed. | |
| Agent decides | Planner chooses the minimum that still supports dummy registration and future tool growth. | |

**User's choice:** Metadata + view factory + capability flags.
**Notes:** The shell should know enough to route navigation, output, and job affordances cleanly.

---

## Shell And Navigation Feel

### First Window Feel

| Option | Description | Selected |
|--------|-------------|----------|
| Compact production bench | Sidebar/tool list, focused tool surface, shared output/jobs nearby but restrained. | ✓ |
| Dashboard hub | Larger overview with tool cards, recent outputs, and status panels up front. | |
| Agent decides | Planner chooses the shell layout that best fits native macOS conventions. | |

**User's choice:** Compact production bench.
**Notes:** The app should feel fast and calm during a Cubase session.

### Output Inbox Visibility

| Option | Description | Selected |
|--------|-------------|----------|
| Always reachable, not dominant | Present as a sidebar/footer/detail area or navigation item, but the active tool remains primary. | ✓ |
| Prominent main pane | Make outputs a central part of the first screen, almost equal to tools. | |
| Settings-only for now | Configure output folder in Phase 1, but do not build much visible inbox surface yet. | |

**User's choice:** Always reachable, not dominant.
**Notes:** Output handoff matters, but the inbox should support the tool UI rather than take it over.

### Launch Target

| Option | Description | Selected |
|--------|-------------|----------|
| First registered tool | Open directly into the dummy/dev tool in Phase 1, and later the most useful real tool. | ✓ |
| Output inbox | Start from recent generated files and let tools be chosen from navigation. | |
| Neutral welcome/setup view | Explain output folder/settings before using tools. | |

**User's choice:** First registered tool.
**Notes:** Keep the app action-oriented.

### UI Copy Density

| Option | Description | Selected |
|--------|-------------|----------|
| Terse labels and actionable empty states | Minimal copy, only enough to orient and recover. | ✓ |
| More guidance early | Include short explanations for each shared surface while the app is young. | |
| Agent decides | Let the UI spec/planner tune the amount of copy. | |

**User's choice:** Terse labels and actionable empty states.
**Notes:** This is a production utility, not onboarding-heavy software.

---

## Output Inbox, Settings, Jobs

### Output Inbox Reality

| Option | Description | Selected |
|--------|-------------|----------|
| Real persisted inbox model | Store output items with file URL, source tool, created date, status/metadata fields, and reveal/drag affordances when available. | ✓ |
| Folder setting only | Persist the output folder now; build item metadata later. | |
| Agent decides | Planner chooses the smallest inbox foundation that still supports future tools. | |

**User's choice:** Real persisted inbox model.
**Notes:** Later file-producing tools need one shared output contract.

### Output Folder Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| User-chosen folder with sensible default | Default to an app folder in Music or Documents, but let the user choose and persist it. | ✓ |
| Fixed app-managed folder | Keep everything under Application Support for simplicity. | |
| Agent decides | Planner picks based on macOS file-access constraints. | |

**User's choice:** User-chosen folder with sensible default.
**Notes:** Local handoff matters, so the user should be able to point it somewhere practical for Cubase work.

### Job System Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Shared job model + lightweight runner | Queued, running, completed, failed, canceled, progress, message/log field, and cancellation hook. | ✓ |
| Status model only | Define the states now, but defer progress/cancel mechanics until real jobs arrive. | |
| Agent decides | Planner picks the smallest job foundation that satisfies Phase 1. | |

**User's choice:** Shared job model + lightweight runner.
**Notes:** Conversion, recording, and downloads will all inherit this foundation.

### Settings Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Output folder + audio preset defaults + helper paths | Include the key shared settings now, even if helper paths are mostly health placeholders until later phases. | ✓ |
| Output folder only | Keep Phase 1 settings minimal; add presets/helper paths in later feature phases. | |
| Agent decides | Planner decides how much settings surface is worth creating now. | |

**User's choice:** Output folder + audio preset defaults + helper paths.
**Notes:** FND-05 explicitly names audio defaults and helper tool paths.

---

## the agent's Discretion

- Exact Swift protocol/type shape for the feature registry and tool context.
- Exact default output folder path, provided it is sensible, local, user-changeable, and persisted.
- Exact persistence implementation for settings and output metadata.
- Exact placement of the always-reachable output inbox in the compact shell.

## Deferred Ideas

None.
