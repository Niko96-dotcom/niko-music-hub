# Autonomous backlog — 2026-05-25

## Picked (music-66)

Prove **song warnings list** panel/export parity (`song=` / `warning=` rows vs in-app **Songs with warnings** section) in fixture E2E and smoke.

## Completed (music-66)

- `ArchiveDiagnosticsSongWarningsPanelContext` for panel line + export `song=` / `warning=` parity
- User-flow smoke prints `diagnostics_panel_song_warnings_lines` with match marker
- E2E asserts each panel song-warning line maps to export `song=` and `warning=` rows and `songs_with_warnings=1`
- Unit tests: `testFixtureScanSongWarningsPanelMatchesExporter`
- `docs/user-e2e.md` updated for song-warnings panel parity
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-65)

Prove **skipped-at-roots list** panel/export parity (`LOOSE_FILE.txt`, `README.md`) in fixture E2E and smoke.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
