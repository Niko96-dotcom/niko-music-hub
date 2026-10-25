# NMH-022 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Menu bar extra Search Archive…

| Check | Result |
|-------|--------|
| Extra item Search Archive… (ellipsis) | **PASS** |
| Order includes Open, Search Archive…, Archive Browser, tools, Output Inbox, Quit | **PASS** |
| No Settings in extra | **PASS** |

## Verdict

**fixed**

Clicking Search Archive with closed window not separately timed; label/order Accept met via menu bar 2 AX dump.
