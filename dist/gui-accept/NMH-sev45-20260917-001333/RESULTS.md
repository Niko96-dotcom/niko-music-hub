# Sev3 leftover + Sev5 GUI Accept — 2026-09-17 ~00:26 CEST

Proof: `dist/gui-accept/NMH-sev45-20260917-001333/`
Suite: `NikoMusicHubGUIAcceptSev45.020604E9-D1F1-4CC4-AF7B-AFDD79EDCB19`
Fixture: `Fixtures/CubaseArchive` + `DRY_RUN_OPEN=1` + isolated `output-inbox.json` Ready row.
Sev4 trio (004/009/062) already fixed at tip `3ebf26d` by parallel Accept — not re-committed here.

| ID | Verdict | Evidence |
|----|---------|----------|
| NMH-030 | **PASS** | Ready inbox row `ready-fixture-beat.wav` + persistent **Reveal**/**Open** (`ax-full2.txt`); VO actions Reveal in Finder / Open / Analyze BPM (`ax-030-row.txt`); grip always-visible in code (accessibilityHidden decorative) |
| NMH-036 | **PASS** | `HubDesignSystemTokenTests.testUITypeMeetsTenPointFloor` PASS (`unit-tests.txt`) — compact/UI type ≥ 10 pt |
| NMH-028 | **PASS** (caveat) | `HubDesignComponentsTests.testChoiceChipsWrapAtNarrowWidthAndMeetDefaultHeight` PASS; Downloader chips visible (`ax-dl.txt` / `ax-028-chips-final.txt`). Reduce Motion hover-not-animate not runtime-proven unattended. |
| NMH-024 | **IAR** | `testHighContrastSecondaryDiffersFromStandard` PASS (tokens differ) but System Settings → Increase Contrast light/dark visual Accept not run (would change user a11y while asleep). |
| NMH-025 | **IAR** | Tab focused an AXTextField once, but Song Detail quiet-field 2 pt `Palette.focus` ring not screenshot/AX-proven. |
| NMH-038 | **IAR** | RTL layout direction not forced unattended. |
| NMH-043 | **IAR** | Downloader error-card unit wiring OK (`DownloaderTrustAndErrorTests`); shipping Recorder/BPM/incompatible-macOS card actions not GUI-proven this pass. |
| NMH-074 | **IAR** | Code/tokens appearance-dependent sheen + Reduce Transparency skip present; light/dark visual rim not screenshot-proven. |
| NMH-006 | **IAR** | unchanged — arrow selection Selected trait not proven |
| NMH-035 | **IAR** | unchanged — Space taps OK prior; focus-ring visibility not proven |
| NMH-088 | **IAR** | unchanged — menu Skip PASS prior; Option-arrow playhead not proven |

Unit suites also green this session: ArchiveAccessRecoveryTests, DownloadStallMonitorTests, DownloaderViewModelTests, HubDesignSystemTokenTests, HubDesignComponentsTests, HubSurfaceTests, DownloaderTrustAndErrorTests.
