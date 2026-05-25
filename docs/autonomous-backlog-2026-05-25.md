# Autonomous backlog — 2026-05-25

## Picked (music-59)

Diagnostics panel: surface **Active search** (query, match count, per-match explainability) with export parity — `active_search` was export-only while operators triaged fuzzy matches.

## Completed (music-59)

- `ArchiveDiagnosticsSearchPanelContext` for panel query/match lines and export parity checks
- Diagnostics panel shows **Active search** when a query is active (matches `ArchiveDiagnosticsSearchContext`)
- `ArchiveUserFlowSmoke` + smoke stdout: `diagnostics_panel_search_query_line_match=`, `diagnostics_panel_search_match_lines_match=`
- E2E asserts panel search lines against export `search_query=` / `search_match title=`
- Unit tests: `ArchiveDiagnosticsSearchPanelContextTests`
- `docs/user-e2e.md` documents new parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-58)

Diagnostics panel: prove `main_preview_summary=` / `preview_rank_line=` panel surfacing matches export on Preview Ranking Lab.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
- Diagnostics: panel/export parity for **active skipped search** (export `active_skipped_search` block; sidebar already lists matches)
