# Autonomous backlog — 2026-05-25

## Picked (music-68)

Prove **global warning** panel/export parity (`global_warning=` rows vs in-app scan diagnostics warning lines) on the invalid-root smoke pass.

## Completed (music-68)

- `ArchiveDiagnosticsGlobalWarningsPanelContext` for panel line text + export `global_warning=` parity
- Invalid-root user-flow smoke asserts panel global warning lines match export
- E2E asserts `diagnostics_panel_invalid_root_global_warning_lines_match=` and per-line `global_warning=` rows
- Unit tests: `ArchiveDiagnosticsGlobalWarningsPanelContextTests`
- `docs/user-e2e.md` updated for global-warning panel parity
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-67)

Prove **scan count rows** panel/export parity (`Songs` / `Song warnings` vs `songs=` / `songs_with_warnings=` / `total_song_warnings=`) in fixture E2E and smoke.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
