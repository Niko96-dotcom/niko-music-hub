# Autonomous backlog — 2026-05-25

## Picked (music-62)

Diagnostics panel: prove **Active search** panel/export parity for fuzzy scan-warning triage (`ncpr fnd` → Broken Folder Example) — export-only checks left operators unsure the in-app panel matched support exports.

## Completed (music-62)

- `activeSearchPanelParity` helper in `ArchiveUserFlowSmoke` (reusable for future search flows)
- Fuzzy scan-warning flow asserts panel query/match lines match export `active_search` block
- Smoke stdout: `diagnostics_panel_fuzzy_warning_search_*_match=` markers
- E2E asserts panel lines against export `search_query=` / `search_matches=` / `search_match title=…`
- Unit test: `testFixtureFuzzyScanWarningSearchPanelMatchesExporter`
- `docs/user-e2e.md` documents new markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-61)

Diagnostics panel: surface **Selected song** (title, CPR summary, warnings, sidecar notes) with export parity.

## Next best TODO

- Extend active-search panel/export parity to remaining fixture searches (warning `project`, notes `nts nly`, folder `brkn fld`, CPR `neohkv2`, preview `ranking lab v3 mx`) using the shared helper
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
