# Leftover Accept retry — NMH-leftovers-retry-20260917-011335

Date: 2026-09-17 ~01:13–01:27 CEST
Base tip at start: `70b2a06`. Focus-claim + `canSkipPreview` firstResponder-only gate committed with this Accept.
Fixture: CubaseArchive + DRY_RUN_OPEN=1 + isolated suite; no ~/Music writes.
App: rebuilt into this proof dir (`NMHBuildID` 1.5.4+70b2a06…).

## NMH-088 — PASS

Amber Moth preview **playing** (`PLAY=Pause preview`, duration 3:20).
With Song Skip menu enabled after focus claim / `canSkipPreview` fix:

| action | delta | excess over wall | file |
|--------|------:|-----------------:|------|
| Option-Right | +5.300s | +4.782 | `ax-088i-measure.json` |
| Option-Left | −4.700s | −5.198 | same |
| Song menu Skip Forward | +5.300s | +4.776 | same |
| Song menu Skip Back | −4.800s | −5.323 | same |
| Button Skip forward | +5.100s | +4.673 | same |

Also `menu_en=true` (`ax-088i-menu-en.txt`), playing proof `ax-088i-playing.txt`, capture `captures/088i.png`.
Units previously green: `ArchivePreviewSeekRelativeTests` 4/4.

## NMH-035 — still IAR

- **Tab → Tap Tempo:** `FOCUSED=AXButton|Tap Tempo` (`ax-035-tab-0.txt`, `ax-035i-focus.txt`)
- **Dark ring visible:** `captures/035i-tab-dark.png` / `035-tab-dark.png` (blue system focus ring on pad)
- **Space tap:** still `Current BPM=Not recorded` after Space (`ax-035i-after-space.txt`) — not proven
- **Light matrix:** no successful light screenshot this pass

## NMH-006 — still IAR

List open + CG click Neon; Return dump shows `Reveal in Finder` but no AX `SEL` move on Down (`ax-006i-*`). Navigator units still green.

## NMH-043 — still IAR

No StandardErrorCard in fixture Recorder GUI (`ax-043i-recorder.txt`).

## NMH-132 / NMH-133 — still IAR

System menu-bar appearance / FKA overlay not flipped unattended (asleep / System Settings).

## Blockers noted

Transient macOS “Grok Bot möchte auf Daten aus anderen Apps zugreifen” sheet blocked GUI mid-run; dismissed with **Nicht erlauben**.
