# Autonomous backlog — 2026-05-25

## Picked (music-32)

Per-song `too_short_non_main` breakdown lines in diagnostics export for support triage (`too_short_song=<title> count=<n> clips=<names>`).

## Completed (music-32)

- `TooShortNonMainSongBreakdown` + `tooShortSongBreakdowns` on preview-ranking panel context
- `ArchiveDiagnosticsExporter` writes one `too_short_song=` line per affected song under `preview_ranking_panel`
- User-flow smoke + E2E assert Ranking Lab breakdown in ranking-lab export file
- Tests: `ArchiveDiagnosticsPreviewRankingPanelContextTests`, `ArchiveDiagnosticsExporterTests`, view-model export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-31)

Machine-readable preview-ranking panel counts in diagnostics export for offline parsing (`too_short_non_main=`, `songs_with_too_short=`).

## Prior completed (music-31)

- `ArchiveDiagnosticsExporter` writes `too_short_non_main=` and `songs_with_too_short=` under `preview_ranking_panel`
- User-flow smoke + E2E assert non-zero counts in ranking-lab export file
- Tests: `ArchiveDiagnosticsExporterTests`, `ArchiveBrowserViewModelTests`, smoke export match guard
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Archive diagnostics panel UI: show per-song too-short breakdown inline (export-only today)
