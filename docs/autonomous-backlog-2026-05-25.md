# Autonomous backlog — 2026-05-25

## Picked (music-33)

Surface per-song too-short preview breakdown inline in the archive diagnostics panel (was export-only after music-32).

## Completed (music-33)

- `TooShortNonMainSongBreakdown.panelDisplayLine` for operator-facing panel copy
- `ArchiveDiagnosticsPanelView` lists each affected song under "Too short previews (not main)"
- Test: `ArchiveDiagnosticsPreviewRankingPanelContextTests.testTooShortBreakdownPanelDisplayLine`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-32)

Per-song `too_short_non_main` breakdown lines in diagnostics export for support triage (`too_short_song=<title> count=<n> clips=<names>`).

## Prior completed (music-32)

- `TooShortNonMainSongBreakdown` + `tooShortSongBreakdowns` on preview-ranking panel context
- `ArchiveDiagnosticsExporter` writes one `too_short_song=` line per affected song under `preview_ranking_panel`
- User-flow smoke + E2E assert Ranking Lab breakdown in ranking-lab export file
- Tests: `ArchiveDiagnosticsPreviewRankingPanelContextTests`, `ArchiveDiagnosticsExporterTests`, view-model export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-31)

Machine-readable preview-ranking panel counts in diagnostics export for offline parsing (`too_short_non_main=`, `songs_with_too_short=`).

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: parsed version tiebreak edge cases and stronger duration plausibility explainability in UI
