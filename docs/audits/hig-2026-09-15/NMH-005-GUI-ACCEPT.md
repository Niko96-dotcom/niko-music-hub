# NMH-005 GUI Accept (2026-09-16 ~00:05 CEST)

Shared proof: `dist/gui-accept/NMH-sev3-20260916-235736/` (fixture CubaseArchive via `NIKO_MUSIC_HUB_FIXTURE_ROOT`, isolated suite `NikoMusicHubGUIAcceptSev3.18493CF1-9A0C-41E9-B661-A3265D5A17B7`, `DRY_RUN_OPEN=1`, no live ~/Music writes; settings left at suite default).

## Board workflow via Song menu (no drag)

| Check | Result |
|-------|--------|
| Song menu → Move to… lists workflow columns | **PASS** (`nmh005-move.txt`) |
| Move Neon Hook → Songstarter/Beat without drag | **PASS** — No Status 9→8; Songstarter/Beat 0→1 (`ax-005.txt`) |
| Drag still available (not disabled) | **PASS** — board cards still present; drag not removed |

VoiceOver-only path not separately exercised; keyboard/menu path satisfies Accept.

## Verdict

**fixed**

Proof dir shared sev3 session. App binary tip at launch: v1.5.4+92fa3a0.
