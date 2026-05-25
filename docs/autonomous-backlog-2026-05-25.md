# Autonomous backlog — 2026-05-25

## Picked (music-27)

Export diagnostics from user-flow smoke when warning search is active; E2E greps `search_match title=Broken Folder Example` in the export file.

## Completed (music-27)

- `ArchiveUserFlowSmoke` exports diagnostics after warning-token search and asserts `search_match title=Broken Folder Example` in export text
- `ArchiveUserFlowSmokeResult` carries warning export path + match flag for smoke stdout
- `ArchiveSmokeCommands` prints `diagnostics_export_warning_path` and `diagnostics_export_warning_match`
- `script/e2e_user_smoke.sh` verifies warning export file contains `search_match title=Broken Folder Example`
- Tests: `ArchiveUserFlowTests` warning export assertions; `ArchiveBrowserViewModelTests.testExportDiagnosticsIncludesWarningSearchContext`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-26)

Export diagnostics from user-flow smoke when song search is active; E2E greps `search_match title=Neon Hook` in the export file.

## Prior completed (music-26)

- `ArchiveUserFlowSmoke` exports diagnostics after neon hk search and asserts `search_match title=Neon Hook` in export text
- `ArchiveUserFlowSmokeResult` carries search export path + match flag for smoke stdout
- `ArchiveBrowserViewModel.exportDiagnostics` uses per-export unique filenames so song/skipped exports do not overwrite
- `ArchiveSmokeCommands` prints `diagnostics_export_search_path` and `diagnostics_export_search_match`
- `script/e2e_user_smoke.sh` verifies search export file contains `search_match title=Neon Hook`
- Tests: `ArchiveUserFlowTests` search export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking v0.2: parsed version tiebreak, duration plausibility, extension tiebreak, stronger explainability in export/UI
