# Autonomous backlog — 2026-05-25

## Picked (music-55)

Diagnostics panel: prove Preview Ranking Lab scan callout and selected header match export (`preview_ranking_scan_callout=`, `preview_ranking_selected_header=`) — parity gap after tiebreak panel proofs in music-53/54.

## Completed (music-55)

- `ArchiveUserFlowSmoke` panel/export parity for **Preview Ranking Lab** scan callout and selected header
- Smoke stdout: `diagnostics_panel_ranking_scan_callout_match=`, `diagnostics_panel_ranking_selected_header_match=`
- E2E asserts panel strings equal export `preview_ranking_scan_callout=` and `preview_ranking_selected_header=`
- Unit test: scan header callout matches exporter line
- `docs/user-e2e.md` documents ranking-lab parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-54)

Diagnostics panel: prove version and extension preview tiebreak callouts match export (`preview_rank_tiebreak=`) on their fixtures — parity gap after duration tiebreak panel proof in music-53.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
