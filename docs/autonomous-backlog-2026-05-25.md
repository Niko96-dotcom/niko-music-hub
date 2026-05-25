# Autonomous backlog — 2026-05-25

## Picked (music-64)

Prove **fuzzy skipped-entry search** (`lse fle` → `LOOSE_FILE.txt`) with active skipped-search panel/export parity in fixture E2E and smoke.

## Completed (music-64)

- User-flow smoke uses fuzzy query `lse fle` with `fuzzy skipped label` explainability
- `activeSkippedSearchPanelParity` helper mirrors song-search parity pattern
- E2E `assert_active_skipped_search_panel_parity` helper
- Unit tests: `testFindsLooseFileByFuzzyLabelSubsequence`, `testFixtureFuzzyLooseFileSkippedSearchPanelMatchesExporter`
- `docs/user-e2e.md` updated for fuzzy skipped search
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-63)

Extend **Active search** panel/export parity to all remaining fixture fuzzy searches using `activeSearchPanelParity` (warning `project`, notes `nts nly`, folder `brkn fld`, CPR `neohkv2`, preview `ranking lab v3 mx`).

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
