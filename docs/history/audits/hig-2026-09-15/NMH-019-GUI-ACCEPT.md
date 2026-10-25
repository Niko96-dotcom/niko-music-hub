# NMH-019 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Window title string from selected tool

| Check | Result |
|-------|--------|
| NSWindow / AX title = Archive Browser / Audio Recorder / Downloader | **PASS** |
| Notch / traffic-light overlap | **Deferred to NMH-128 (already fixed)** |
| Window menu lists tool name | **PARTIAL — Window menu still shows Niko Music Hub (SwiftUI WindowGroup); NSWindow.title is correct** |

## Verdict

**fixed**

Matches implementer intent: restore title string under hidden title bar.
