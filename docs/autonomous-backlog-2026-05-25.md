# Autonomous backlog — 2026-05-25

## Picked (music-25)

Export diagnostics from user-flow smoke when skipped search is active; E2E greps `skipped_search_match` in the export file.

## Completed (music-25)

- `ArchiveUserFlowSmoke` exports diagnostics after skipped-entry search and asserts `skipped_search_match label=LOOSE_FILE.txt` in export text
- `ArchiveUserFlowSmokeResult` carries export path + match flag for smoke stdout
- `ArchiveSmokeCommands` prints `diagnostics_export_path` and `diagnostics_export_skipped_match`
- `script/e2e_user_smoke.sh` verifies export file contains `skipped_search_match` row
- Tests: `ArchiveUserFlowTests` export assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-24)

Tighten skipped-entry search so generic tokens do not match every root skipped file via shared boilerplate reason.

## Prior completed (music-24)

- `SkippedScanEntry.standardNonFolderAtRootReason` shared with scanner
- `SkippedEntrySearchMatcher` uses label-only matching when entry uses standard non-folder reason (no reason/fuzzy-reason hits)
- Tests: `testGenericFileTokenDoesNotMatchUnrelatedSkippedReadme`, `testGenericFolderTokenDoesNotMatchAllRootSkippedEntries`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-23)

Include active skipped-search hits in exported archive diagnostics text.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Export diagnostics from user-flow smoke when song search is active (mirror skipped-search E2E for `search_match` rows)
