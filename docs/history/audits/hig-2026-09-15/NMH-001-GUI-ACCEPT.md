# NMH-001 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Settings in App menu / ⌘,

| Check | Result |
|-------|--------|
| App menu shows Settings… (ellipsis) | **PASS** |
| ⌘, opens Settings window (General pane / SwiftUI Settings) | **PASS** |
| Full Keyboard Access: ⌘, with tools sidebar hidden | **PASS** |
| Archive / main window remains while Settings open | **PASS — W:General + W:Niko Music Hub** |

## Verdict

**fixed**

Proof dir shared shell sev2 session. Settings suite used defaults (no corrupt settings blob).
