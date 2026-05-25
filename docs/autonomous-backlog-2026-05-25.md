# Autonomous backlog — 2026-05-25

## Picked (music-23)

Include active skipped-search hits in exported archive diagnostics text.

## Completed (music-23)

- `ArchiveDiagnosticsSkippedSearchContext` + match rows for export
- `ArchiveDiagnosticsExporter` writes `active_skipped_search` section with query, match count, label/kind/summary per hit (paths redacted)
- `ArchiveBrowserViewModel` passes `activeSkippedSearchExportContext()` on export
- Tests: `ArchiveDiagnosticsSkippedSearchContextTests`, `ArchiveBrowserViewModelTests.testExportDiagnosticsIncludesSkippedSearchContext`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-22)

Index skipped-root labels in archive search for operator drill-down (e.g. `LOOSE_FILE.txt`).

## Prior completed (music-22)

- `SkippedEntrySearchMatcher` matches query tokens against skipped-entry label/reason with explainability
- `ArchiveBrowserViewModel` exposes `skippedSearchMatches` alongside song filter
- Sidebar shows “Skipped matches” when search hits root-level skipped entries
- User-flow smoke + E2E grep: `skipped_search_query=LOOSE_FILE.txt`, label, `skipped label` summary
- Tests: `SkippedEntrySearchMatcherTests`, `ArchiveBrowserViewModelTests.testSearchFindsSkippedRootLabel`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-21)

Redact dry-run CPR paths in smoke stdout/logs; add `skipped_entries` count to diagnostics export.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Tighten skipped fuzzy matching so generic tokens (e.g. `file`) do not over-match unrelated skipped README entries
- Export diagnostics from user-flow smoke when skipped search is active (grep `skipped_search_match` in export file)
