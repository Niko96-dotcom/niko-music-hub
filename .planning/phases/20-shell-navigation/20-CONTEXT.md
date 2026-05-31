# Phase 20: Shell & Navigation - Context

**Gathered:** 2026-05-31
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — recommendations auto-accepted)

<domain>
## Phase Boundary

Reshape app chrome into one cohesive glass shell: `AppShellView` spacing/centering/collapsed rails/window default, `ToolSidebarView` icon+label navigation and health strip, `OutputInboxInspectorView` header/cards/empty state per spec §6. Delete `ArchiveDesignTokens.swift` and migrate all archive references to `HubDesignSystem.Colors` + inline `Color.primary`/`Color.secondary` per spec §3.3 mapping.

Requirements SH-01 through SH-04 locked in `.planning/REQUIREMENTS.md`. Carry forward Phase 19 intent-first spec fidelity (D-01), hub accent (D-03), reduce motion (D-08).

**Out of scope:** Tool page layouts (Phases 21–22), archive sidebar/detail redesign (Phases 23–24), per-tool `HubLabeledButton` rollout beyond shell/inbox if not required for SH-*.

</domain>

<decisions>
## Implementation Decisions

### Shell layout (SH-01)
- **S-01:** Use `HubDesignSystem.Spacing.shell` (10) in `AppShellView` — already tokenized in Phase 19; verify padding/HStack spacing and collapsed rails only.
- **S-02:** **Do not** change every tool view in Phase 20 — add a shared `HubToolContentColumn` (or extend `HubToolLayout`) wrapper in AppCore that applies centering pattern from spec §4.2; apply in `AppShellView` around `activeToolView` so all tools center without editing BPM/converter/etc. this phase.
- **S-03:** Collapsed sidebar rails: `Colors.accentTint` hover + respect `accessibilityReduceMotion` (Phase 19 D-08).
- **S-04:** Toolbar toggle buttons: SF Symbols `.hierarchical` rendering per §4.4.
- **S-05:** Default window `1280×820` in `NikoMusicHubApp` (or app entry) per §4.5; keep existing `minWidth` logic in `AppShellView`.

### Tool sidebar (SH-02)
- **S-06:** Header shows app name + **app version from bundle** (`CFBundleShortVersionString`), not hardcoded "v1.0" — subtitle "Local tools" removed per §5.1.
- **S-07:** Tool rows: icon 18×18 hierarchical + label 13pt medium; selected uses `Colors.accent` label + `accentTint`/`selectedStroke` row chrome; row height ~36px.
- **S-08:** Health strip: 7px `StatusDot`, typography/padding per §5.4; keep glass card wrapper.

### Output inbox (SH-03)
- **S-09:** Header "Output" + path on second line; folder button right-aligned on title row; remove redundant "Output folder" label.
- **S-10:** Empty state vertically centered with icon + copy per §6.2.
- **S-11:** Output cards horizontal layout; extension-based file icon; drag grip on hover only; context menu + single-click reveal; no in-card Finder button.
- **S-12:** Remove weak `Divider().opacity(0.4)` — use `Spacing.section` gap only.

### Archive token migration (SH-04)
- **S-13:** Delete `ArchiveDesignTokens.swift` after mechanical replacement in all 14 consumer files (grep list).
- **S-14:** Mapping per spec §3.3: `background`/`surface` → `Color.clear`; `accent` → `HubDesignSystem.Colors.accent`; `warning` → `HubDesignSystem.Colors.warning`; `textPrimary`/`textSecondary` → `Color.primary`/`.secondary`.
- **S-15:** No visual redesign of archive views beyond token swap — archive layout polish is Phase 23–24.

### Claude's Discretion
- Exact `HubToolContentColumn` API naming/placement (AppCore vs NikoMusicHub target).
- Whether inbox card single-click vs context-menu-only for reveal (spec says single-click reveal — implement that).

</decisions>

<canonical_refs>
## Canonical References

- `docs/UI-REDESIGN-PLAN.md` — §4 Shell, §5 Tool Sidebar, §6 Output Inbox, §3.3 token deletion map, §14 Wave 2
- `.planning/REQUIREMENTS.md` — SH-01–SH-04
- `.planning/phases/19-design-system-foundation/19-CONTEXT.md` — D-01, D-03, D-08
- `Sources/NikoMusicHub/AppShell/AppShellView.swift`
- `Sources/NikoMusicHub/AppShell/ToolSidebarView.swift`
- `Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift`
- `Sources/FeatureArchiveBrowser/ArchiveDesignTokens.swift` (delete)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 19 landed `HubDesignSystem`, `HubGlassChrome`, `HubIconButton` hover, `HubToolLayout.maxContentWidth` 680.
- `HubSidebarNavRow` in `HubGlassChrome` — extend or mirror for labeled tool rows.

### Established Patterns
- `AppShellView` already uses `HubDesignSystem.Spacing.shell` and glass panels.
- Archive views heavily reference `ArchiveDesignTokens` (14 files) — mechanical migration.

### Integration Points
- `ToolRegistry` / `activeToolView` — wrap feature content for centering without per-feature edits.
- `OutputInboxInspectorView` uses `context.outputFolderURL` and job/output models from AppCore.

</code_context>

<specifics>
## Specific Ideas

- Auto-accepted smart discuss tables (shell centering via shared wrapper, bundle version in sidebar, inbox interaction per spec §6.3).

</specifics>

<deferred>
## Deferred Ideas

- Per-tool content centering inside ScrollViews if shell wrapper insufficient — address in Phases 21–22.
- Archive sidebar toolbar/chips redesign — Phase 23.

</deferred>

---

*Phase: 20-Shell & Navigation*
*Context gathered: 2026-05-31*
