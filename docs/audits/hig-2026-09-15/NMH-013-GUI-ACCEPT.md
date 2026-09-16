# NMH-013 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Tools menu tool switching

| Check | Result |
|-------|--------|
| Tools menu lists Archive Browser + production tools + Settings | **PASS** |
| With sidebar hidden, Tools → Audio Recorder | **PASS — window title Audio Recorder** |
| Tools → Settings opens Settings window | **PASS** |
| ⌘1 returns Archive Browser | **PASS** |

## Verdict

**fixed**
