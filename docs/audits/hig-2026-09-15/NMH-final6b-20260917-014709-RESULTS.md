# NMH-final6b RESULTS (2026-09-17 01:53 CEST)

Proof: `dist/gui-accept/NMH-final6b-20260917-014709`
Working tree tip at test: dirty on `de1ab83` lineage (soft-seal `7cdd3bf` rejected).
Suite: NikoMusicHubGUIAcceptFinal6B.3686042F-D16B-46BB-BD4D-CBF2ABA7460D

## NMH-006 — IAR (partial fix kept)

- `handleArchiveMoveCommand` + `.focusable(true)` (not `.edit`; bare `.focusable()` fails typecheck)
- NSEvent local arrow monitor (`installArchiveArrowKeyMonitor`) — binary contains symbol
- Units: ArchiveSongSelectionNavigatorTests + ArchiveShortcutFocusPolicyTests PASS
- **Return opens detail: PASS** (`ax-006g-return-hit.txt` / `ax-006h-return-hit.txt`)
- **Arrow SEL move: FAIL** (stuck on Neon Hook; NSScrollView still eats arrows under CG/HID; monitor not proven in Accept)
- **Space preview toggle: FAIL** under unattended keys

## NMH-035 — IAR (new evidence)

- Tab → Tap Tempo FOCUSED in Light and Dark: PASS (`ax-035j-focus-light.txt`, `ax-035k-focus-dark.txt`)
- Screenshots: `captures/035-tab-light.png`, `captures/035-tab-dark.png` (+ prior `035i-tab-dark.png`)
- **Space → BPM leaves Not recorded: FAIL** (keytopid/HID). Click/AXPress records BPM (e.g. 171) — not Accept-complete.

## Skipped

- NMH-043 / 132 / 133 left IAR (reject soft final6 seal)
