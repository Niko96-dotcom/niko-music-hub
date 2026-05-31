# Milestone Context: v1.3 Full UI Redesign

**Captured:** 2026-05-31
**Source:** `docs/UI-REDESIGN-PLAN.md`

## Goal

Ship the full visual redesign of Niko Music Hub — warm indigo accent, liquid-glass depth, labeled primary actions, and page-specific density — without changing product behavior or archive intelligence semantics.

## North Star

**"A music producer's trusted workshop"** — warm, confident, quiet. Xcode meets Apple Music meets Linear.

## Seven Design Rules (non-negotiable)

1. Every primary action button gets icon + short text label.
2. Parallel controls share height and alignment.
3. Three emphasis levels only: primary / secondary / tertiary per action row.
4. Cards for bounded content; dividers + whitespace for flowing detail views.
5. Warm accent (`#5A6BF2`), cool-neutral shell background.
6. Purposeful motion (hover, selection) — no gratuitous animation.
7. Density matches page purpose (dense archive sidebar, spacious BPM tapper).

## Implementation Waves (from spec §14)

Execute in dependency order — **do not reorder waves across phases**:

| Wave | Scope | GSD Phase |
|------|--------|-----------|
| 1 | Design system foundation | 19 |
| 2 | Shell & navigation + token deletion | 20 |
| 3 | BPM, Recorder, Converter | 21 |
| 3 | Downloader, Settings | 22 |
| 4 | Archive sidebar & browse surfaces | 23 |
| 4 | Archive detail, first-run, panels | 24 |
| 5 | Shared polish + visual regression | 25 |

## Key Constraints

- Preserve all accessibility labels and `help` tooltips from v1.2.
- Keep three-column shell layout; refine spacing and centering only.
- Delete `ArchiveDesignTokens.swift` and `HubCompactChipColors+Archive.swift` when replacements land.
- File manifest: 2 create, 2 delete, 33 modify — see spec §15.

## Autonomous Execution

Run: `/gsd-autonomous` (or `/gsd-autonomous --interactive` for discuss on grey areas).

Phases 19–25 are frontend-heavy — expect `gsd-ui-phase` / `gsd-ui-review` during autonomous runs.
