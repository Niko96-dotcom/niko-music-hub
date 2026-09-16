# NMH-069 GUI Accept — Shell vibrancy when window inactive

Date: 2026-09-17 00:45 CEST
Proof: `dist/gui-accept/NMH-sev6a-20260917-004028/`
Suite: `NikoMusicHubGUIAcceptSev6a.68BD2CAC-9858-483F-AFCB-D13551DF22D5`
App: tip-aligned `1.5.4+ff61d2492c1b` (commit `ff61d24` at launch; Accept commit follows)
Fixture: `Fixtures/CubaseArchive` + `DRY_RUN_OPEN=1` + isolated suite; no ~/Music writes.

## Accept

1. Click another app; hub chrome vibrancy goes inactive (less vibrant) and/or the tint dims. Click hub; it returns to active. **PASS**

## Evidence

- Active window screenshot: `captures/069-active.png`
- Inactive (Finder frontmost): `captures/069-inactive.png`
- Re-activated: `captures/069-reactivated.png`
- Sidebar compare crop: `captures/069-sidebar-compare.png`
- Pixel means (sidebar crop): active RGB≈(74.9,76.8,79.9) → inactive ≈(65.4,67.0,70.1) → reactivated matches active
- SHA-256 differs active vs inactive; reactivated ≈ active
- Source: `HubVisualEffectView.isActive` + `controlActiveState == .key` in `HubMaterial.swift` / `HubGlassChrome.swift` (implement `6d79953`)

## Verdict

**PASS**
