# Phase 1: App Foundation and Tool Architecture - Context

**Gathered:** 2026-05-04T11:49:56+02:00
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 establishes the native macOS app foundation for Outside Cubase Hub: app shell, registered tool navigation, feature registry boundary, shared tool context, settings persistence, output inbox model, and shared job primitives. It must prove that a dummy feature can be registered and shown without editing existing feature internals. It does not implement BPM tapping, conversion, recording, or downloading beyond foundation contracts/placeholders needed by later phases.

</domain>

<decisions>
## Implementation Decisions

### Feature Registry Shape
- **D-01:** Tools must register through a feature boundary and receive shared services through a tool context rather than wiring themselves directly into shell internals.
- **D-02:** The planner/agent may choose the exact Swift protocol/type shape, as long as the feature boundary remains clean and testable.
- **D-03:** Phase 1 should show only real registered tools. A dummy/dev feature is acceptable for proving registration, but do not show disabled roadmap placeholders for BPM, conversion, recording, or downloading.
- **D-04:** Registration should live in a static app composition root at startup. Feature modules should not mutate global registration state or self-register automatically in Phase 1.
- **D-05:** Each tool should expose metadata, a view factory, and capability flags from day one. Metadata should be sufficient for navigation; capability flags should let the shell understand whether a tool produces files and/or jobs.

### Shell And Navigation Feel
- **D-06:** The app shell should feel like a compact production bench: focused, native, calm, and action-oriented for use during a Cubase session.
- **D-07:** Use a sidebar/tool-list style primary navigation with the active tool as the main focus. Avoid a marketing-style dashboard or large overview-first layout.
- **D-08:** The output inbox should be always reachable but not dominant. It supports handoff; it should not swallow the active tool UI.
- **D-09:** On launch, open directly into the first registered tool. In Phase 1 this can be the dummy/dev tool; later it should become the most useful real tool.
- **D-10:** Use terse labels and actionable empty states. The shell should not over-explain itself.

### Output Inbox, Settings, Jobs
- **D-11:** Phase 1 should create a real persisted output inbox model, not merely an output folder setting.
- **D-12:** Output inbox items should be ready to carry at least file URL, source tool, created date, state/status, and metadata fields that later tools can extend.
- **D-13:** The output folder should have a sensible default, but the user must be able to choose a practical local folder and have that choice persist.
- **D-14:** Phase 1 should include a shared job model plus lightweight runner covering queued, running, completed, failed, and canceled states.
- **D-15:** The job foundation should include progress, a message/log field, and a cancellation hook so conversion, recording, and downloading do not invent separate job mechanics later.
- **D-16:** Settings should include output folder, audio preset defaults, and helper tool paths. Helper-path behavior can stay light until converter/downloader phases, but the persistence shape should exist now.

### the agent's Discretion
- Exact protocol names, type names, and module/file layout are flexible if they preserve the locked feature boundary.
- Exact default output folder location is flexible, but it should be sensible for local Cubase handoff and user-changeable.
- Exact persistence mechanism for settings/output metadata is flexible if it is local, testable, and durable across launches.
- Exact visual arrangement of the always-reachable output inbox is flexible if the active tool remains primary.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope And Requirements
- `.planning/ROADMAP.md` — Phase 1 goal, success criteria, planned slices, dependencies, and phase boundary.
- `.planning/REQUIREMENTS.md` — FND-01 through FND-05 foundation requirements plus v1 constraints and traceability.
- `.planning/PROJECT.md` — Core value, out-of-scope boundaries, platform constraints, and project-level architecture decisions.
- `.planning/STATE.md` — Current phase/status and accumulated initialization decisions.

### Research Guidance
- `.planning/research/SUMMARY.md` — Consolidated architecture, feature, stack, and pitfall findings for the project.
- `.planning/research/ARCHITECTURE.md` — Recommended feature registry, ports/adapters, job runner, output inbox, and module boundaries.
- `.planning/research/STACK.md` — Swift/SwiftUI/AppKit, AVFoundation, Core Audio, FFmpeg, and yt-dlp stack guidance.
- `.planning/research/FEATURES.md` — Feature dependencies and MVP expectations, especially registry, output inbox, tool health, and shared presets.
- `.planning/research/PITFALLS.md` — Phase 1 anti-patterns, especially hard-coded feature hubs and unsafe future helper-tool boundaries.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No app source exists yet. Phase 1 is expected to create the first source structure.
- Planning research docs are the primary reusable assets for this phase; they define the intended SwiftUI shell, feature registry, shared job/output services, and adapter boundaries.

### Established Patterns
- Use native Swift/SwiftUI with AppKit interop where it helps file and Finder workflows.
- Keep shared contracts in a small app/core layer; keep feature modules isolated behind a registry and tool context.
- Keep long-running work behind shared job primitives from the start.
- Treat output files as first-class inbox items with metadata and handoff actions, not just files in a folder.

### Integration Points
- New app composition root: owns static registration of tool features.
- Tool context: supplies shared settings, output inbox, job runner, file/Finder actions, diagnostics, and later helper-tool services.
- Settings persistence: must support output folder, audio preset defaults, and helper paths across launches.
- Output inbox persistence: must accept future output items from conversion, recording, and downloader features.

</code_context>

<specifics>
## Specific Ideas

- The app should feel like a compact production bench rather than a dashboard.
- The first screen should be directly useful: open into the first registered tool, not a neutral welcome screen.
- Future tool placeholders should not appear until the corresponding phases implement real tools.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope.

</deferred>

---

*Phase: 01-app-foundation-and-tool-architecture*
*Context gathered: 2026-05-04T11:49:56+02:00*
