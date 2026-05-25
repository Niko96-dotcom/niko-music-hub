# Autonomous backlog — 2026-05-25

## Picked (music-24)

Tighten skipped-entry search so generic tokens do not match every root skipped file via shared boilerplate reason.

## Completed (music-24)

- `SkippedScanEntry.standardNonFolderAtRootReason` shared with scanner
- `SkippedEntrySearchMatcher` uses label-only matching when entry uses standard non-folder reason (no reason/fuzzy-reason hits)
- Tests: `testGenericFileTokenDoesNotMatchUnrelatedSkippedReadme`, `testGenericFolderTokenDoesNotMatchAllRootSkippedEntries`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-23)

Include active skipped-search hits in exported archive diagnostics text.

## Prior completed (music-23)

- `ArchiveDiagnosticsSkippedSearchContext` + match rows for export
- `ArchiveDiagnosticsExporter` writes `active_skipped_search` section with query, match count, label/kind/summary per hit (paths redacted)
- `ArchiveBrowserViewModel` passes `activeSkippedSearchExportContext()` on export
- Tests: `ArchiveDiagnosticsSkippedSearchContextTests`, `ArchiveBrowserViewModelTests.testExportDiagnosticsIncludesSkippedSearchContext`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-22)

Index skipped-root labels in archive search for operator drill-down (e.g. `LOOSE_FILE.txt`).

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Export diagnostics from user-flow smoke when skipped search is active (grep `skipped_search_match` in export file)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
