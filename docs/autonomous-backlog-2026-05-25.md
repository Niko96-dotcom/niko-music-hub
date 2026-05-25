# Autonomous backlog — 2026-05-25

## Picked (music-63)

Extend **Active search** panel/export parity to all remaining fixture fuzzy searches using `activeSearchPanelParity` (warning `project`, notes `nts nly`, folder `brkn fld`, CPR `neohkv2`, preview `ranking lab v3 mx`).

## Completed (music-63)

- `activeSearchPanelParity` wired for warning, notes, folder, CPR, and preview fixture searches
- Smoke stdout markers: `diagnostics_panel_{warning,notes,folder,cpr,preview}_search_*`
- E2E `assert_active_search_panel_parity` helper (reuses fuzzy-warning pattern)
- Unit test: `testFixtureScanWarningSearchPanelMatchesExporter`
- `docs/user-e2e.md` table of all active-search parity prefixes
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-62)

Fuzzy scan-warning (`ncpr fnd`) active-search panel/export parity.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
