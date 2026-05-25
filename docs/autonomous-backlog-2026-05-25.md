# Autonomous backlog — 2026-05-25

## Picked (music-58)

Diagnostics panel: prove `main_preview_summary=` / `preview_rank_line=` panel surfacing matches export on Preview Ranking Lab — selected header embedded summary but export lines were not smoke-proven in panel.

## Completed (music-58)

- `ArchiveDiagnosticsPreviewRankingPanelContext` helpers for selected-song main summary and ranked preview lines with export parity checks
- Diagnostics panel shows **Main preview ranking** and **All previews (ranked)** when a song is selected
- `ArchiveUserFlowSmoke` + smoke stdout markers: `diagnostics_panel_ranking_main_preview_summary_match=`, `diagnostics_panel_ranking_preview_rank_lines_match=`
- E2E asserts panel `main_preview_summary=` and each `preview_rank_line=` against export
- Unit tests: main summary and ranked lines panel/export parity
- `docs/user-e2e.md` documents new parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-57)

Diagnostics panel: prove preview-ranking tiebreak legend in panel matches export (`preview_ranking_tiebreak_legend=`) on Preview Ranking Lab.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
- Archive diagnostics: richer export of scan health trends / multi-root diff (if operator asks)
