# Phase 22: Tool UI — Downloader & Settings - Context

**Gathered:** 2026-05-31
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — recommendations auto-accepted)

<domain>
## Phase Boundary

Redesign Downloader and Settings per `docs/UI-REDESIGN-PLAN.md` §11–12 and TOOL-04/TOOL-05. Glass URL row with inline Download, horizontal format chips, trust card with `LabeledContent`. Settings: centered layout, section importance hierarchy, labeled archive/helper/output actions. No archive browse/detail (Phases 23–24), no final polish pass (Phase 25).

</domain>

<decisions>
## Implementation Decisions

### Downloader URL row (TOOL-04)
- **D-01:** Replace `.roundedBorder` field with `hubGlassCard` row: link icon 13pt tertiary, padding H12 V10, trailing labeled Download + icon-only Clear.
- **D-02:** Download: `HubLabeledButton` or `.borderedProminent` labeled "Download"; Clear: `xmark.circle.fill` plain tertiary.
- **D-03:** Center tool column like Phase 21 tools (`maxWidth` HubToolLayout, centered in scroll).

### Format chips (TOOL-04)
- **F-01:** Remove glass card wrapper; inline strip: "Download as:" + mutually exclusive text chips (Audio only / Video + audio).
- **F-02:** Format/quality via `Menu` chip showing current selection (WAV, Best, etc.) — not full-width pickers.

### Trust & progress (TOOL-04)
- **T-01:** Trust card: `shield.lefthalf.filled` accent, section title "Download details", `LabeledContent` for Source/Format/Output, trust notice 10pt italic tertiary.
- **T-02:** Progress bar tint `HubDesignSystem.Colors.accent`; log `Typography.mono(size: 10)`, max height 140.

### Settings hierarchy (TOOL-05)
- **S-01:** Header: `Typography.screenTitle()` "Settings", 12pt secondary subtitle; no gear icon in title.
- **S-02:** `SettingsSection.importance`: `.high` (General, Output, Cubase archive), `.medium` (Audio conversion, Recording), `.low` (Privacy, Helper tools, About — title + indented content, no card).
- **S-03:** Inner card padding 12 (was 14); medium sections use muted glass (primary opacity ~0.04 fill).

### Labeled actions (TOOL-05)
- **A-01:** Archive: "Add Root" `HubLabeledButton` secondary; Remove stays icon trash with destructive role; rows include `folder.fill`.
- **A-02:** Output: labeled Choose Folder + Reveal in Finder (`HubLabeledButton`).
- **A-03:** Helpers: `LabeledContent` rows with path or "Auto-detect", Choose… bordered small, Clear xmark when custom path set.
- **A-04:** Privacy: labeled "Open System Settings" for screen/audio recording.

### Claude's Discretion
- Downloader header may stay compact status line (not full screenTitle) to preserve tool identity in sidebar context.
- Format chip styling may reuse private text-chip helper in DownloaderView (no new AppCore type unless reused elsewhere).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HubLabeledButton`, `HubDesignSystem`, `hubGlassCard`, `hubToolContentPadding()`, `HubToolLayout.maxContentWidth`.

### Established Patterns
- Phase 21 centered tool columns; Phase 20 shell already centers tool content.

### Integration Points
- `DownloaderViewModel`, `SettingsView` + `archiveViewModel` — UI-only; preserve download/settings behavior and existing tests.

</code_context>

<specifics>
## Specific Ideas

- Auto-accepted smart discuss aligned with UI-REDESIGN-PLAN §11–12.

</specifics>

<deferred>
## Deferred Ideas

- Archive sidebar chips/cards — Phase 23.
- StandardErrorCard polish — Phase 25.

</deferred>
