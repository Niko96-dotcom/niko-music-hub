# NMH-046 GUI Accept (2026-09-16 ~00:05 CEST)

Shared proof: `dist/gui-accept/NMH-sev3-20260916-235736/` (fixture CubaseArchive via `NIKO_MUSIC_HUB_FIXTURE_ROOT`, isolated suite `NikoMusicHubGUIAcceptSev3.18493CF1-9A0C-41E9-B661-A3265D5A17B7`, `DRY_RUN_OPEN=1`, no live ~/Music writes; settings left at suite default).

## Context menus share Song menu actions

| Check | Result |
|-------|--------|
| Board Control-click: Open Project, Play Preview, Reveal in Finder, Move to… | **PASS** (`ax-046-menus.txt`) |
| List Control-click: same order | **PASS** (`ax-046-list-items.txt`) |
| Broken Folder: Open Project + Play Preview disabled, Reveal enabled | **PASS** (`ax-046-broken-enabled.txt` enabled=0/0/1) |
| Titles match Song menu (NMH-034) | **PASS** |

## Verdict

**fixed**

Proof dir shared sev3 session. App binary tip at launch: v1.5.4+92fa3a0.
