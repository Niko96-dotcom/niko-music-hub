# Autonomous backlog — 2026-05-25

## Picked (music-22)

Index skipped-root labels in archive search for operator drill-down (e.g. `LOOSE_FILE.txt`).

## Completed (music-22)

- `SkippedEntrySearchMatcher` matches query tokens against skipped-entry label/reason with explainability
- `ArchiveBrowserViewModel` exposes `skippedSearchMatches` alongside song filter
- Sidebar shows “Skipped matches” when search hits root-level skipped entries
- User-flow smoke + E2E grep: `skipped_search_query=LOOSE_FILE.txt`, label, `skipped label` summary
- Tests: `SkippedEntrySearchMatcherTests`, `ArchiveBrowserViewModelTests.testSearchFindsSkippedRootLabel`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-21)

Redact dry-run CPR paths in smoke stdout/logs; add `skipped_entries` count to diagnostics export.

## Prior completed (music-21)

- `ArchiveUserFlowSmokeResult` exposes `dryRunCPRDisplayPath` and `dryRunLogDisplayLine` via `Song.displayDryRunPath` / `DiagnosticsPathRedactor`
- `ArchiveSmokeCommands` prints redacted `cpr_path` and dry-run log lines (no raw home prefix in operator logs)
- `ArchiveBrowserViewModel` dry-run helper line uses redacted path
- `ArchiveDiagnosticsExporter` header includes `skipped_entries=N`
- Tests: `SongDisplayTests`, `ArchiveDiagnosticsExporterTests`, `ArchiveUserFlowTests`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-20)

E2E user-flow smoke: assert warning-token search finds Broken Folder with scan-warning explainability.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Archive diagnostics UX: include skipped-search hits in exported diagnostics text
- Tighten skipped fuzzy matching so generic tokens (e.g. `file`) do not over-match unrelated skipped README entries
