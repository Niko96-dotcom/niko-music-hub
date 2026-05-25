# Autonomous backlog — 2026-05-25

## Picked (music-54)

Diagnostics panel: prove version and extension preview tiebreak callouts match export (`preview_rank_tiebreak=`) on their fixtures — parity gap after duration tiebreak panel proof in music-53.

## Completed (music-54)

- `ArchiveUserFlowSmoke` panel/export parity for **Equal Score Version Tiebreak** and **Equal Score Extension Tiebreak** callouts
- Smoke stdout: `diagnostics_panel_version_tiebreak_callout_match=`, `diagnostics_panel_extension_tiebreak_callout_match=`
- E2E asserts panel callout text equals export `preview_rank_tiebreak=` on both fixtures
- `docs/user-e2e.md` documents version/extension tiebreak parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-53)

Diagnostics panel: dedicated preview tiebreak callout when a song is selected (export `preview_rank_tiebreak=` parity) and user-flow/E2E proof that panel selected header + callout match export on the duration tiebreak fixture.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
