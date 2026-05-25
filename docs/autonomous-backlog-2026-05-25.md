# Autonomous backlog — 2026-05-25

## Picked (music-28)

Export diagnostics after selecting Preview Ranking Lab; E2E greps `selected_song_title=Preview Ranking Lab` and `preview_rank_line=.*v3` in the export file.

## Completed (music-28)

- `ArchiveUserFlowSmoke` selects Preview Ranking Lab, exports diagnostics, asserts export contains selected song + `preview_rank_line` with v3
- `ArchiveUserFlowSmokeResult` carries ranking-lab export path + match flag for smoke stdout
- `ArchiveSmokeCommands` prints `diagnostics_export_ranking_path` and `diagnostics_export_ranking_match`
- `script/e2e_user_smoke.sh` verifies ranking export file contains selected song title and v3 preview rank line
- Tests: `ArchiveUserFlowTests` ranking export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-27)

Export diagnostics from user-flow smoke when warning search is active; E2E greps `search_match title=Broken Folder Example` in the export file.

## Prior completed (music-27)

- `ArchiveUserFlowSmoke` exports diagnostics after warning-token search and asserts `search_match title=Broken Folder Example` in export text
- `ArchiveUserFlowSmokeResult` carries warning export path + match flag for smoke stdout
- `ArchiveSmokeCommands` prints `diagnostics_export_warning_path` and `diagnostics_export_warning_match`
- `script/e2e_user_smoke.sh` verifies warning export file contains `search_match title=Broken Folder Example`
- Tests: `ArchiveUserFlowTests` warning export assertions; `ArchiveBrowserViewModelTests.testExportDiagnosticsIncludesWarningSearchContext`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking v0.2 core signals are in place; next slice is richer operator UI (tiebreak legend, duration-too-short callouts in diagnostics panel header)
