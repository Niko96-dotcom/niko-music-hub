# Phase 2: BPM Tapper - Context

**Gathered:** 2026-05-04T15:25:03+02:00
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 delivers the first useful native tool in Outside Cubase Hub: an offline BPM tapper that replaces opening an external website during a Cubase session. The tool must support mouse and keyboard tapping, a live BPM estimate from recent taps, graceful handling of early taps and obvious mistakes, reset, half-time/double-time adjustment, copy, save, and local BPM history. It also validates that a real tool can plug into the Phase 1 feature-module architecture.

This phase does not implement audio-file BPM/key/loudness analysis, global shortcuts outside the app, Cubase project integration, or naming-template/sample-prep workflows.

</domain>

<decisions>
## Implementation Decisions

### Tap Feel
- **D-01:** Taps are accepted through a focused tap zone. Mouse clicks count only inside the big BPM tap surface; keyboard taps count when the BPM tool is active.
- **D-02:** Spacebar is the only keyboard input for tapping tempo.
- **D-03:** After a long pause, the next tap starts a fresh tap run instead of carrying stale intervals forward.
- **D-04:** Reset must be available through both a visible Reset button and the Escape key.

### Tempo Estimator
- **D-05:** BPM is calculated from a recent interval average, with guardrails for unusual taps.
- **D-06:** The estimate should use the last 4 intervals.
- **D-07:** The UI should show the first BPM estimate after 2 taps, then stabilize as more taps arrive.
- **D-08:** Obvious outlier intervals should be ignored for the estimate while keeping the current tap run alive.

### Result Actions
- **D-09:** Half-time and double-time are adjustment modes. They change the displayed and saved result while preserving the original tapped BPM as context.
- **D-10:** Copy writes a plain number to the clipboard, such as `128`, not `128 BPM` or a richer summary.
- **D-11:** Save is a one-click action that saves the current displayed result to local history.
- **D-12:** Copy and Save show a small inline confirmation near the action, not a system notification.

### History Shape
- **D-13:** Saved history entries contain BPM, timestamp, and adjustment context indicating whether the value is original, half-time, or double-time.
- **D-14:** The BPM tool main view shows a recent saved-history list.
- **D-15:** Each history row has a copy action for that row's saved BPM.
- **D-16:** Phase 2 includes a Clear all history action, but not individual row deletion.

### the agent's Discretion
- Exact timeout threshold for "long pause" is flexible, but must be short enough that stale taps do not poison the next tempo.
- Exact outlier detection thresholds are flexible, but must be covered by estimator tests.
- Exact BPM rounding/display precision is flexible; keep it production-practical and make clipboard output a plain number.
- Exact layout of the tap surface, action buttons, and recent list is flexible if the tool stays compact, native, and fast to operate.
- Exact local persistence mechanism for BPM history is flexible if it is durable across launches and testable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope And Requirements
- `.planning/ROADMAP.md` - Phase 2 goal, success criteria, planned slices, dependency on Phase 1, and phase boundary.
- `.planning/REQUIREMENTS.md` - BPM-01 through BPM-05 and UX-04 keyboard shortcut expectations.
- `.planning/PROJECT.md` - Core value, active BPM requirement, out-of-scope boundaries, and current Phase 1 state.
- `.planning/STATE.md` - Current project status and accumulated decisions affecting Phase 2.

### Prior Architecture Decisions
- `.planning/phases/01-app-foundation-and-tool-architecture/01-CONTEXT.md` - Locked feature registry, compact production-bench shell, output/settings/job foundations, and integration expectations.

### Research Guidance
- `.planning/research/FEATURES.md` - BPM tapper table stakes, MVP expectations, and the existing online tapper reference.
- `.planning/research/ARCHITECTURE.md` - Recommended BPM Tapper flow, feature module structure, use-case boundaries, and testable module guidance.
- `.planning/research/STACK.md` - Swift, SwiftUI, AppKit interop, XCTest, and native macOS stack guidance.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/AppCore/Features/ToolFeature.swift` and `Sources/AppCore/Features/ToolRegistry.swift` define the feature boundary Phase 2 must use.
- `Sources/OutsideCubaseHub/AppComposition.swift` is the static composition root where the BPM feature should be registered.
- `Sources/OutsideCubaseHub/DevTool/DevToolFeature.swift` is the closest existing example of a feature exposing metadata and a SwiftUI view through `makeView(context:)`.
- `Sources/AppCore/Services/ToolContext.swift` provides shared services. BPM history persistence may either use an existing service appropriately or add a small feature-local persistence boundary.
- `Tests/AppCoreTests/FeatureRegistryTests.swift` shows the current test style for registration behavior.

### Established Patterns
- The app is a Swift Package Manager macOS app targeting macOS 14.2.
- Tool registration is static at startup and ordered by `AppComposition`.
- The shell uses `NavigationSplitView` with the selected tool as the primary surface and the output inbox inspector always reachable.
- Shared core contracts live in `AppCore`; feature-specific behavior should stay out of shell internals.
- Existing tests use XCTest and small focused test cases.

### Integration Points
- Add a BPM feature module and register it in `AppComposition`.
- Replace or follow the dev feature as the first real useful registered tool.
- Keep BPM estimator logic separate from SwiftUI so tap math, pause behavior, half/double adjustment, and outlier handling can be tested directly.
- Add local history persistence without turning BPM history into a file-producing output inbox workflow.

</code_context>

<specifics>
## Specific Ideas

- The tool should feel faster and calmer than opening an online BPM tapper.
- Clipboard output should be a plain number for easy paste into Cubase or production notes.
- History should be useful during a session without turning save into a note-taking or filing workflow.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within Phase 2 scope.

</deferred>

---

*Phase: 02-bpm-tapper*
*Context gathered: 2026-05-04T15:25:03+02:00*
