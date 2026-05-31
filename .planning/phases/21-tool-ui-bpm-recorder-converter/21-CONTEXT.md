# Phase 21: Tool UI — BPM, Recorder, Converter - Context

**Gathered:** 2026-05-31
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — recommendations auto-accepted)

<domain>
## Phase Boundary

Redesign BPM Tapper, Audio Recorder, and WAV Converter tool pages per `docs/UI-REDESIGN-PLAN.md` §8–10 and requirements TOOL-01–TOOL-03. Centered spacious layouts, hero readouts (`Typography.display()` 56pt), `HubLabeledButton` for primary action rows, refined drop zone / meter / batch badges. No Downloader or Settings (Phase 22), no archive UI (Phases 23–24).

Carry forward Phase 19–20: intent-first spec fidelity, `HubDesignSystem` tokens, labeled primary actions, reduce motion for hover/tap feedback.

</domain>

<decisions>
## Implementation Decisions

### BPM Tapper (TOOL-01)
- **B-01:** Center entire workflow column (`maxWidth` 560); section title via `Typography.screenTitle()`.
- **B-02:** Hero BPM: `Typography.display()` centered; "BPM" suffix 14pt tertiary; tap count 12pt tertiary centered.
- **B-03:** Tap pad min height 240, max width 560; surface subtitle "Tap or press Space" only (status stays in page header).
- **B-04:** Tap feedback: `scaleEffect(0.98)` ~100ms on tap; respect `accessibilityReduceMotion`.
- **B-05:** Actions: `HubLabeledButton` — Copy BPM / Save BPM (primary) / Reset; `Spacing.controlGap`.
- **B-06:** History: `Divider` tinted `Colors.separator`; "Clear History" labeled destructive button.

### Audio Recorder (TOOL-02)
- **R-01:** Center column; timer hero `Typography.display()` + `.monospacedDigit()`; idle `.tertiary`, recording `.primary`.
- **R-02:** Meter 8px height, radius 4, track `primary.opacity(0.06)`, fill gradient success→warning→danger by peak; glow shadow when recording.
- **R-03:** Record/Stop: `.borderedProminent`, `.controlSize(.large)`, red tint; pulsing red dot as leading icon while recording (no separate dot).
- **R-04:** Max Duration label above segmented picker; 24px gap above picker section.
- **R-05:** Save toast banner top of scroll content: success tint background, labeled Reveal/Open, auto-dismiss 5s.

### WAV Converter (TOOL-03)
- **C-01:** Drop zone: 1.5px dashed `Colors.separator` / accent when targeted; `arrow.down.doc` 28pt; "Choose Files" `HubLabeledButton`; min height 180.
- **C-02:** Preset strip: pipe-separated values + labeled "Edit Preset" toggles editor (not icon-only).
- **C-03:** Actions: Add Files / Convert (primary) / Stop — all `HubLabeledButton`.
- **C-04:** Batch rows: 7px status dot, source type capsule pill, `Colors.accent` progress tint, converter label on metadata line.

### Claude's Discretion
- History row copy remains icon-only (tertiary in list).
- Permission/error cards: labeled buttons where touched; full permission redesign deferred.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HubLabeledButton`, `HubDesignSystem.Typography.display()`, `HubToolLayout.maxContentWidth`, `hubToolContentPadding()`, `hubGlassCard()`.

### Established Patterns
- Phase 20 `hubToolContentColumn()` centers tool content in shell; tool views use `ScrollView` + max width 640.

### Integration Points
- `BPMTapperViewModel`, `AudioRecorderViewModel`, `AudioConverterViewModel` — UI-only; preserve behavior and tests.

</code_context>

<specifics>
## Specific Ideas

- Auto-accepted smart discuss aligned with UI-REDESIGN-PLAN §8–10 and ROADMAP success criteria.

</specifics>

<deferred>
## Deferred Ideas

- Downloader / Settings glass URL field — Phase 22.
- Archive browse/detail polish — Phases 23–24.

</deferred>
