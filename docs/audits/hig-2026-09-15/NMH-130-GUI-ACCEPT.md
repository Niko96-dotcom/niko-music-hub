# NMH-130 GUI Accept — Window frame restoration

Date: 2026-09-17 00:59 CEST
Proof: `dist/gui-accept/NMH-leftovers-20260917-005751/`
Suite: `NikoMusicHubGUIAcceptLeftovers.6C3FD8FA-7153-496E-ABA6-E1E40B9ACB31`
App: tip-aligned with uncommitted `setFrameAutosaveName("hub.main")` baked into proof bundle (commit follows)
Fixture: `Fixtures/CubaseArchive` + `DRY_RUN_OPEN=1` + isolated suite; no ~/Music writes.

## Accept

1. Resize/move hub window; quit; relaunch; frame restores. **PASS**

## Evidence

- Dirty fix: `HubWindowChromeConfigurator.swift` sets `window.setFrameAutosaveName("hub.main")` in addition to `isRestorable` + identifier `hub.main` (identifier alone failed at sev6).
- Before resize: `ax-130-before-resize.txt` → 1400×900 @ 40,40
- After resize: `ax-130-after-resize.txt` / `ax-130-after-nudge.txt` → 1111×777 @ 151,91
- Defaults after quit: `ax-130-defaults-after-quit.txt` → `151 249 1111 777 ...`
- After relaunch: `ax-130-after-relaunch.txt` → **1111×777 @ 151,91** (matches saved frame)
- Screenshot: `captures/130-restored.png`

## Verdict

**PASS**
