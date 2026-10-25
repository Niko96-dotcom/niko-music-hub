# NMH-012 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## View menu + shortcuts for sidebar/inbox

| Check | Result |
|-------|--------|
| Title-bar Hide tools sidebar (AX id=sidebar.leading) | **PASS — hub_tool_ count 7→0** |
| Restore via View → Show Tools Sidebar | **PASS — 0→7** |
| Title-bar Hide output inbox (AX id=sidebar.trailing) | **PASS** |
| Restore via View → Show Output Inbox / ⌘⌥I | **PASS** |
| ⌘⌥S toggle | **PASS (observed in session)** |

## Verdict

**fixed**

System Events button-by-description failed (invalid index); Swift AXPress on AXIdentifier worked.
