# NMH-014 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Help menu + Helper Tools

| Check | Result |
|-------|--------|
| Help → Niko Music Hub Help | **PASS — sections Archive roots, Helper tools, Output Inbox** |
| Help → Helper Tools opens Settings Helpers | **PASS** |
| ⌘? | **Menu path PASS; AXMenuItemCmdChar not exposed; code registers keyboardShortcut("?", .command)** |

## Verdict

**fixed**
