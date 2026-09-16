# NMH-129 GUI Accept (2026-09-16 CEST)

Fixture suite: isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1`.
Proof dir: `dist/gui-accept/NMH-129-20260916-211417/` (local; not committed binaries).

## Menu presence (live dump)

- Menus: Niko Music Hub, Edit, View, Tools, Song, Window, Help. **No File menu.**
- **Undo** present under Edit (⌘Z); enabled=false until a text field has an undoable edit (not confirmed enabled in this run).
- **Enter Full Screen** under View (system, often disabled) and under Window after fix (our command, enabled=true).
- **Close** / **Minimize** under Window (system Close often disabled; our Close enabled after fix).
- **New Window**: absent (expected after NMH-127 single `Window`).

## Shortcut checklist

| Action | Result |
|--------|--------|
| ⌘M Minimize | **PASS** (`AXMinimized=true`) |
| ⌘W Close | **PASS** after fix (`ax_windows` 1→0; process stays for MenuBarExtra) |
| Window > Close (enabled) | **PASS** (`ax_windows` 1→0) |
| ⌃⌘F / Enter Full Screen | **FAIL** in this session (`AXFullScreen` stays false; size stays 1280×820) |
| ⌘Z Undo in text field | **NOT CONFIRMED** (Undo stayed disabled after Settings/Song attempts) |
| File > New Window | **PASS** (absent by design) |

## Code change (this Accept)

- Added `HubWindowCommandGroup` + `HubWindowChromeActions` (Close/Minimize/Full Screen menu + local key monitor for ⌘W/⌘M/⌃⌘F).
- `HubWindowChromeConfigurator`: insert `.fullScreenPrimary`.
- Wired into `NikoMusicHubApp` commands + `applicationDidFinishLaunching`.

System Close remained disabled and ate ⌘W until the key monitor called `NSWindow.close()` on `hub.main`.

## Verdict

- Close + Minimize restored and verified.
- Full Screen still does not enter full screen in fixture GUI session — leave **implemented-awaiting-runtime** until FS is proven (or root-caused).
- Undo still needs a focused text-field proof on a later pass.

## Follow-up (2026-09-16 21:45 CEST)
Style mask titled/closable/miniaturizable/resizable forced (`913b3c5`). Retest still `AXFullScreen=false` at 1280×820 for ⌃⌘F and Window > Enter Full Screen. Close/Minimize remain PASS.

## Follow-up (2026-09-16 23:08 CEST)

Retest after focused FS fix attempt (`HubWindowChromeActions.forceKey` + deferred `toggleFullScreen`, stronger `collectionBehavior` managed/fullScreenPrimary, key-monitor ignores capsLock bits). Proof: `dist/gui-accept/NMH-129-fs-20260916-230828/`.

| Check | Result |
|-------|--------|
| ⌃⌘F | **FAIL** (`AXFullScreen=false`, size 1280×820; key monitor often did not fire in this session) |
| Window > Enter Full Screen | **FAIL** (menu action ran; debug showed `appActive=true`, `mainWin=hub.main`, but `keyWindow=nil` / `isKey=false` despite `canBecomeKey=true`; `toggleFullScreen` no-op, `fsBit=false`) |
| AX set `AXFullScreen=true` | **FAIL** (stays false) |
| Close / Minimize | unchanged **PASS** from earlier Accept |

Also tried `.windowStyle(.titleBar)` temporarily — did **not** fix FS; reverted to `.hiddenTitleBar`.

**Root cause note:** in this unattended fixture GUI session the main window never becomes key (`NSApp.keyWindow` stays nil while app is active). AppKit Full Screen appears to require a key window. Leave **implemented-awaiting-runtime** until FS is proven in an interactive session (or a different key-window ownership fix is found). Undo still not confirmed.
