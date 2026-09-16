# NMH-017 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Selected tool restored across launches

| Check | Result |
|-------|--------|
| Quit on Downloader | **PASS — title Downloader; suite hub.shell.selectedToolID=downloader** |
| Relaunch without -ui-tool restores Downloader | **PASS — persisted id downloader** |

## Verdict

**fixed**

-ui-tool override path exercised earlier in overnight runs; this Accept proved persist/restore.
