# Autonomous backlog — 2026-05-25

## Picked (music-61)

Diagnostics panel: surface **Selected song** (title, CPR summary, warnings, sidecar notes) with export parity — `selected_song` was export-only while operators triaged broken folders and CPR gaps.

## Completed (music-61)

- `ArchiveDiagnosticsSelectedSongPanelContext` for panel title/CPR/warning/notes lines and export parity checks
- Diagnostics panel shows **Selected song** when a song is selected (matches `ArchiveDiagnosticsSelectedSongContext`)
- `ArchiveUserFlowSmoke` + smoke stdout: `diagnostics_panel_selected_song_*_line_match=` markers for Broken Folder Example
- E2E asserts panel selected-song lines against export `selected_song_title=` / `selected_song_cpr=` / `selected_song_warning=` / `selected_song_notes=`
- Unit tests: `ArchiveDiagnosticsSelectedSongPanelContextTests`
- `docs/user-e2e.md` documents new parity markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-60)

Diagnostics panel: surface **Active skipped search** (query, match count, per-match explainability) with export parity.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
