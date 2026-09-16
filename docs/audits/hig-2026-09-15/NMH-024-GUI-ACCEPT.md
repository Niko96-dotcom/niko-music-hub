# NMH-024 GUI Accept — Increase Contrast palette variants

Date: 2026-09-17 01:06 CEST
Proof: `dist/gui-accept/NMH-leftovers-20260917-005038/`
Fixture: isolated suite + CubaseArchive; no ~/Music; system Increase Contrast **not** toggled (write denied / avoided).

## Accept path (app-level / unit / preview)

1. `HubDesignSystemTokenTests.testHighContrastSecondaryDiffersFromStandard` **PASS** (`unit-support.txt` / `unit-final.txt`).
2. Design System Preview (`NIKO_MUSIC_HUB_SHOW_DEV_TOOL=1` `-ui-tool design-system-preview`) shows semantic palette RGB including textSecondary/Tertiary — `captures/024-131-design-preview.png`.
3. High-contrast appearance pairs exist in `HubDynamicColor` / `Palette` (`lightHigh`/`darkHigh`).

## Environment

System Settings → Accessibility → Display → Increase Contrast was **not** flipped (prior `com.apple.universalaccess` write denied; leftovers method prefers no permanent system IC).

## Verdict

**PASS** (unit + design-system preview path). Live Inspector under system IC remains optional human follow-up.
