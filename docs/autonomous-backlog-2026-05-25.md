# Autonomous backlog — 2026-05-25

## Picked (music-67)

Prove **scan count rows** panel/export parity (`Songs` / `Song warnings` vs `songs=` / `songs_with_warnings=` / `total_song_warnings=`) in fixture E2E and smoke.

## Completed (music-67)

- `ArchiveDiagnosticsScanCountsPanelContext` for panel count values + export line parity
- User-flow smoke prints `diagnostics_panel_scan_counts_*` with match marker
- E2E asserts panel Songs/Song warnings values map to export count lines
- Unit tests: `ArchiveDiagnosticsScanCountsPanelContextTests` including fixture scan
- `docs/user-e2e.md` updated for scan-count panel parity
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-66)

Prove **song warnings list** panel/export parity (`song=` / `warning=` rows vs in-app **Songs with warnings** section) in fixture E2E and smoke.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
