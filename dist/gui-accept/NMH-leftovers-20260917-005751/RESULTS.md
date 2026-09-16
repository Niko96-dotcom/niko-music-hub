# Leftover Accept RESULTS — NMH-leftovers-20260917-005751

Date: 2026-09-17 ~01:00–01:07 CEST
Base tip at start: `144084d`. NMH-130 accept commits: `37d780c` + ledger `4e68072`.
(Parallel leftovers agent later committed `f8f2eb4` for NMH-024/131.)

Fixture: CubaseArchive + DRY_RUN_OPEN=1 + isolated suite; no ~/Music writes.

## NMH-130 — PASS (committed)

- Fix: `setFrameAutosaveName("hub.main")` in `HubWindowChromeConfigurator.swift`
- Evidence: resize to 1111×777 @ 151,91 → quit → relaunch same frame (`ax-130-*`, `captures/130-restored.png`)
- Defaults: `NSWindow Frame hub.main` = `151 249 1111 777 ...`

## NMH-006 — still IAR

- Units: `ArchiveSongSelectionNavigatorTests` **5/5 PASS** (`unit-006.txt`)
- Click selection sets AX `SEL` on song cards (board + list)
- Unattended arrows/Return/Space: keyboard focus stays on chrome (`Hide tools sidebar` / search); `onMoveCommand` not observed moving selection (`ax-006e-*`, `ax-006f-*`)

## NMH-088 — still IAR

- Song menu titles: **Skip Back 5 Seconds** / **Skip Forward 5 Seconds** present (`ax-088-menu-names.txt`)
- Units: `ArchivePreviewSeekRelativeTests` **4/4 PASS**
- Live Amber Moth preview (3:20): button **Skip forward 5 seconds** moves position **+5.000s** while paused (`ax-088f-btn.txt`)
- Option-Left/Right while paused: **delta 0.0** (`ax-088f-opt.txt`, `ax-088f-optleft.txt`) — Option-seek **not** proven
- Song menu Skip Forward click while paused: **delta 0.0** (`ax-088f-menu.txt`)
- Note: Neon Hook fixture wav is only **0.1s** — useless for seek demos; use Amber/Graffiti (200s)

## NMH-035 — still IAR

- `focusEffectDisabled` absent in source; pad is `.focusable()` + `.focused`
- AX: Tap Tempo receives FOCUS after opening BPM Tapper / clicking pad (`ax-035-*`)
- Screenshot `captures/035-after-click-pad.png` shows a **visible blue system focus ring** around the Tap Tempo pad (click/open focus path)
- Still IAR vs FIX-SPECS Accept: **Tab** to Tap Tempo not proven (Tab stuck on Settings “Follow System”); light+dark ring matrix not run; Space-tap not re-proven this pass

## NMH-043 — still IAR

- No StandardErrorCard appeared in fixture GUI (BPM/Recorder/Downloader)
- Related VM tests PASS (`unit-043.txt`: AudioRecorderViewModelTests, BPMTapperActionsTests, DownloaderTrustAndErrorTests)

## Skipped (asleep / system)

NMH-132 menu-bar appearance, NMH-133 FKA System Settings — left to parallel notes / IAR.
