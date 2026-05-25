# Autonomous backlog — 2026-05-25

## Picked (music-60)

Diagnostics panel: surface **Active skipped search** (query, match count, per-match explainability) with export parity — `active_skipped_search` was export-only while operators triaged root-level skipped files.

## Completed (music-60)

- `ArchiveDiagnosticsSkippedSearchPanelContext` for panel query/match lines and export parity checks
- Diagnostics panel shows **Active skipped search** when a skipped query is active (matches `ArchiveDiagnosticsSkippedSearchContext`)
- `ArchiveUserFlowSmoke` + smoke stdout: `diagnostics_panel_skipped_search_query_line_match=`, `diagnostics_panel_skipped_search_match_lines_match=`
- E2E asserts panel skipped-search lines against export `skipped_search_query=` / `skipped_search_match label=`
- Unit tests: `ArchiveDiagnosticsSkippedSearchPanelContextTests`
- `docs/user-e2e.md` documents new parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-59)

Diagnostics panel: surface **Active search** (query, match count, per-match explainability) with export parity — `active_search` was export-only while operators triaged fuzzy matches.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
