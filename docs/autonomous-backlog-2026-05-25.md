# Autonomous backlog — 2026-05-25

## Picked (music-30)

Export diagnostics preview-ranking panel context: tiebreak legend, scan-wide too-short callout, selected-song header for offline support tickets.

## Completed (music-30)

- `ArchiveDiagnosticsExporter` writes `preview_ranking_panel` section with tiebreak legend and scan callout
- `ArchiveDiagnosticsSelectedSongContext` carries `previewRankingSelectedHeader` for export
- Selected-song export includes `preview_ranking_selected_header=`
- User-flow smoke + E2E assert legend, callout, and selected header in ranking-lab export file
- Tests: `ArchiveDiagnosticsExporterTests.testFormattedTextIncludesPreviewRankingPanelContext`, view-model export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-29)

Preview ranking operator hints in diagnostics panel header: tiebreak legend, scan-wide too-short callouts, selected-song main preview line.

## Prior completed (music-29)

- `ArchiveDiagnosticsPreviewRankingPanelContext`: tiebreak legend, scan-wide too-short non-main counts/callout, selected-song header with skipped too-short alts
- `ArchiveScanDiagnostics` + builder carry `previewRankingPanel` from scan songs
- `ArchiveDiagnosticsPanelView` shows legend, scan callout, and selected-song preview header
- Tests: `ArchiveDiagnosticsPreviewRankingPanelContextTests`, builder assertion for too-short panel context
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Export diagnostics could add `preview_ranking_panel` counts (`too_short_non_main=`, `songs_with_too_short=`) as machine-readable fields
