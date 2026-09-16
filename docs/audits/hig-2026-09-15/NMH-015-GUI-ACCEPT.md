# NMH-015 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Settings as macOS Settings window with panes

| Check | Result |
|-------|--------|
| ⌘, Settings while Archive/main remains | **PASS** |
| Toolbar panes General / Archive / Vault / Helpers / Updates | **PASS** |
| Switch panes (Helpers content) | **PASS** |
| Minimize/zoom | **NOT RUN — system Settings chrome; left as system behavior** |

## Verdict

**fixed**

Corrupt hand-seeded settings JSON previously caused load errors; empty suite → AppSettings.default loads cleanly.
