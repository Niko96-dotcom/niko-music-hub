# Autonomous backlog — 2026-05-25

## Picked (music-65)

Prove **skipped-at-roots list** panel/export parity (`LOOSE_FILE.txt`, `README.md`) in fixture E2E and smoke.

## Completed (music-65)

- `ArchiveDiagnosticsSkippedEntriesPanelContext` for panel line + export `skipped=` parity
- User-flow smoke prints `diagnostics_panel_skipped_entries_lines` with match marker
- E2E asserts each panel skipped line maps to export `skipped=` row and `skipped_entries=2`
- Unit tests: `testFixtureScanSkippedEntriesPanelMatchesExporter`
- `docs/user-e2e.md` updated for skipped-at-roots panel parity
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-64)

Prove **fuzzy skipped-entry search** (`lse fle` → `LOOSE_FILE.txt`) with active skipped-search panel/export parity in fixture E2E and smoke.

## Next best TODO

- **Song warnings list** panel/export parity (`song=` / `warning=` rows vs in-app **Songs with warnings** section)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
