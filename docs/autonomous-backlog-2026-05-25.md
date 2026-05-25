# Autonomous backlog — 2026-05-25

## Picked (music-56)

Diagnostics panel: prove per-song too-short preview breakdown lines match export (`too_short_song=`) on Preview Ranking Lab — parity gap after scan callout/selected header proofs in music-55.

## Completed (music-56)

- `TooShortNonMainSongBreakdown.panelMatchesExport(in:)` ties panel display lines to export `too_short_song=` rows
- `ArchiveUserFlowSmoke` panel/export parity for ranking-lab too-short breakdown
- Smoke stdout: `diagnostics_panel_ranking_too_short_breakdown=`, `diagnostics_panel_ranking_too_short_breakdown_match=`
- E2E asserts panel line names exported clip and export contains matching `too_short_song=` row
- Unit test: ranking-lab breakdown panel/export parity
- `docs/user-e2e.md` documents breakdown parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-55)

Diagnostics panel: prove Preview Ranking Lab scan callout and selected header match export (`preview_ranking_scan_callout=`, `preview_ranking_selected_header=`) — parity gap after tiebreak panel proofs in music-53/54.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
