# Phase 19: Design System Foundation - Context

**Gathered:** 2026-05-31
**Status:** Ready for planning
**Mode:** Interactive discuss (`/gsd-autonomous --interactive`)

<domain>
## Phase Boundary

Land shared design tokens and AppCore components so later phases only compose UI — no ad-hoc colors or mystery icon buttons. Updates `HubDesignSystem`, `HubGlassChrome`, new `HubLabeledButton` and `HubSectionDivider`, and refreshes `HubIconButton`, `StatusDot`, `HubToolLayout`, `HubCompactChipColors` (including archive chip merge). **No consumer feature view changes in this phase** — `./script/ci.sh` green is sufficient.

Requirements DS-01 through DS-08 are locked in `.planning/REQUIREMENTS.md`.

</domain>

<decisions>
## Implementation Decisions

### Spec fidelity
- **D-01:** **Intent-first** — Match visual outcome per `docs/UI-REDESIGN-PLAN.md` §3 and §13; minor Swift/API differences are OK when DS-01–DS-08 and success criteria pass. Do not chase verbatim copy if existing AppCore patterns are cleaner.
- **D-02:** **Typography** — Apply spec font sizes/weights in `HubDesignSystem.Typography` immediately (e.g. `screenTitle` 22→18). Unmigrated views may look slightly off until their phase; no legacy alias layer.
- **D-03:** **Accent** — Use spec warm indigo RGB as `HubDesignSystem.Colors.accent` everywhere the hub owns styling; allow `.accentColor` fallback **only** for system controls the app does not style (native pickers, system chrome we don't wrap).
- **D-04:** **Verification** — Add lightweight SwiftUI preview and/or snapshot tests in AppCoreTests for new/updated primitives (`HubLabeledButton`, `HubSectionDivider`, token smoke) in addition to `./script/ci.sh`.

### Glass & light/dark
- **D-05:** **Parity** — Tune `HubShellBackground`, `HubGlassPanel`, and `HubGlassCard` for **both** dark and light mode in this phase (not dark-only).
- **D-06:** **Materials** — Keep current material choices (e.g. `.thickMaterial` on panels); adjust gradients, shadows, opacities, and inner highlights per spec — do not change material tier without a documented reason.
- **D-07:** **Inner highlight** — Card/panel top highlight is **adaptive**: stronger in dark mode, subtler or omitted in light mode via `@Environment(\.colorScheme)`.
- **D-08:** **Motion** — Hover/selection transitions respect `accessibilityReduceMotion` (instant or minimal animation when enabled).

### Claude's Discretion
- Exact `HubLabeledButton` API shape (loading, disabled, layout) when not specified in UI-REDESIGN-PLAN — follow spec §13.1 intent and existing `HubIconButton` accessibility patterns.
- Whether to extract shared hover helper vs inline `@State` hover on `HubIconButton`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product & requirements
- `docs/UI-REDESIGN-PLAN.md` — §3 Design System Overhaul, §13 Shared Component Library, §14 Wave 1, §15 File Manifest (authoritative visual spec)
- `.planning/REQUIREMENTS.md` — DS-01 through DS-08 acceptance
- `.planning/ROADMAP.md` — Phase 19 goal and success criteria

### Existing implementation (scout)
- `Sources/AppCore/Components/HubDesignSystem.swift` — current tokens to replace/extend
- `Sources/AppCore/Components/HubGlassChrome.swift` — shell/panel/card glass; already uses `colorScheme`
- `Sources/AppCore/Components/HubIconButton.swift` — icon-only actions; 28pt today
- `Sources/AppCore/Components/HubCompactChipColors.swift` — merge `HubCompactChipColors+Archive.swift` in this phase
- `Sources/AppCore/Components/HubToolLayout.swift` — max width 720 today → 680 per spec

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HubGlassChrome` already branches ambient colors and shadows on `colorScheme` — extend opacities per spec rather than new architecture.
- `HubIconButton` used heavily in tools/archive (BPM, converter, downloader, root selection) — size/hover changes here; labeled buttons come online in later phases.
- `HubCompactChipColors+Archive.swift` — delete after merging `.archive` into main enum (DS-08).

### Established Patterns
- AppCore components are `public` for feature modules; no SwiftUI in `NikoMusicCore`.
- Accessibility: labels + `help` on buttons must be preserved (POL-02 in later phase; don't regress in component APIs).

### Integration Points
- Feature views keep compiling unchanged this phase; token renames flow through shared components only.
- `ArchiveDesignTokens.swift` deletion is **Phase 20** (SH-04), not Phase 19.

</code_context>

<specifics>
## Specific Ideas

- Operator trusts `docs/UI-REDESIGN-PLAN.md` as handoff spec; discuss locked intent-first execution and explicit light/dark glass parity.
- Wave 1 in spec §14 is the implementation order for planners/executors.

</specifics>

<deferred>
## Deferred Ideas

- **HubLabeledButton** rollout to BPM/converter/downloader views — Phase 21–22 per roadmap.
- **ArchiveDesignTokens** removal — Phase 20.
- Custom empty-state illustrations, brand font — REQUIREMENTS Future (VIS-01, VIS-02).

</deferred>

---

*Phase: 19-Design System Foundation*
*Context gathered: 2026-05-31*
