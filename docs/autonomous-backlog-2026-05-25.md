# Autonomous backlog — 2026-05-25

## Picked (music-29)

Preview ranking operator hints in diagnostics panel header: tiebreak legend, scan-wide too-short callouts, selected-song main preview line.

## Completed (music-29)

- `ArchiveDiagnosticsPreviewRankingPanelContext`: tiebreak legend, scan-wide too-short non-main counts/callout, selected-song header with skipped too-short alts
- `ArchiveScanDiagnostics` + builder carry `previewRankingPanel` from scan songs
- `ArchiveDiagnosticsPanelView` shows legend, scan callout, and selected-song preview header
- Tests: `ArchiveDiagnosticsPreviewRankingPanelContextTests`, builder assertion for too-short panel context
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-28)

Export diagnostics after selecting Preview Ranking Lab; E2E greps `selected_song_title=Preview Ranking Lab` and `preview_rank_line=.*v3` in the export file.

## Prior completed (music-28)

- `ArchiveUserFlowSmoke` selects Preview Ranking Lab, exports diagnostics, asserts export contains selected song + `preview_rank_line` with v3
- `ArchiveUserFlowSmokeResult` carries ranking-lab export path + match flag for smoke stdout
- `ArchiveSmokeCommands` prints `diagnostics_export_ranking_path` and `diagnostics_export_ranking_match`
- `script/e2e_user_smoke.sh` verifies ranking export file contains selected song title and v3 preview rank line
- Tests: `ArchiveUserFlowTests` ranking export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Export diagnostics could include `preview_ranking_panel=` scan callout + tiebreak legend for offline support tickets
