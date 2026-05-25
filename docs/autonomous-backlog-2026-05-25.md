# Autonomous backlog — 2026-05-25

## Picked (music-26)

Export diagnostics from user-flow smoke when song search is active; E2E greps `search_match title=Neon Hook` in the export file.

## Completed (music-26)

- `ArchiveUserFlowSmoke` exports diagnostics after neon hk search and asserts `search_match title=Neon Hook` in export text
- `ArchiveUserFlowSmokeResult` carries search export path + match flag for smoke stdout
- `ArchiveBrowserViewModel.exportDiagnostics` uses per-export unique filenames so song/skipped exports do not overwrite
- `ArchiveSmokeCommands` prints `diagnostics_export_search_path` and `diagnostics_export_search_match`
- `script/e2e_user_smoke.sh` verifies search export file contains `search_match title=Neon Hook`
- Tests: `ArchiveUserFlowTests` search export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-25)

Export diagnostics from user-flow smoke when skipped search is active; E2E greps `skipped_search_match` in the export file.

## Prior completed (music-25)

- `ArchiveUserFlowSmoke` exports diagnostics after skipped-entry search and asserts `skipped_search_match label=LOOSE_FILE.txt` in export text
- `ArchiveUserFlowSmokeResult` carries export path + match flag for smoke stdout
- `ArchiveSmokeCommands` prints `diagnostics_export_path` and `diagnostics_export_skipped_match`
- `script/e2e_user_smoke.sh` verifies export file contains `skipped_search_match` row
- Tests: `ArchiveUserFlowTests` export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Export diagnostics from user-flow smoke when warning search is active (mirror song/skipped E2E for warning `search_match` rows)
