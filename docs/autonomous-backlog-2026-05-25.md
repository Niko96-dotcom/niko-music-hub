# Autonomous backlog — 2026-05-25

## Picked (music-57)

Diagnostics panel: prove preview-ranking tiebreak legend in panel matches export (`preview_ranking_tiebreak_legend=`) on Preview Ranking Lab — parity gap after too-short breakdown proofs in music-56.

## Completed (music-57)

- `ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegendMatchesExport(in:)` ties panel legend to export line
- `ArchiveUserFlowSmoke` panel/export parity for ranking-lab tiebreak legend
- Smoke stdout: `diagnostics_panel_ranking_tiebreak_legend=`, `diagnostics_panel_ranking_tiebreak_legend_match=`
- E2E asserts panel legend text matches export `preview_ranking_tiebreak_legend=`
- Unit test: tiebreak legend panel/export parity
- `docs/user-e2e.md` documents legend parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-56)

Diagnostics panel: prove per-song too-short preview breakdown lines match export (`too_short_song=`) on Preview Ranking Lab.

## Next best TODO

- Diagnostics panel: prove `main_preview_summary=` / `preview_rank_line=` panel surfacing (or document as export-only) — selected header embeds summary but export lines are not smoke-proven in panel
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
