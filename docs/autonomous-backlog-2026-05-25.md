# Autonomous backlog — 2026-05-25

## Picked (music-21)

Redact dry-run CPR paths in smoke stdout/logs; add `skipped_entries` count to diagnostics export.

## Completed (music-21)

- `ArchiveUserFlowSmokeResult` exposes `dryRunCPRDisplayPath` and `dryRunLogDisplayLine` via `Song.displayDryRunPath` / `DiagnosticsPathRedactor`
- `ArchiveSmokeCommands` prints redacted `cpr_path` and dry-run log lines (no raw home prefix in operator logs)
- `ArchiveBrowserViewModel` dry-run helper line uses redacted path
- `ArchiveDiagnosticsExporter` header includes `skipped_entries=N`
- Tests: `SongDisplayTests`, `ArchiveDiagnosticsExporterTests`, `ArchiveUserFlowTests`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-20)

E2E user-flow smoke: assert warning-token search finds Broken Folder with scan-warning explainability.

## Prior completed (music-20)

- `ArchiveUserFlowSmoke` runs second query `project` after neon open flow
- Smoke output: `warning_search_query`, `warning_search_matches`, `warning_search_match`, `warning_search_summary`
- E2E script greps for Broken Folder + `scan warning` + `project` tokens
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-19)

Surface `sidecarNotes` in song detail UI and diagnostics export (read-only).

## Prior completed (music-19)

- `Song.displaySidecarNotes()` redacts embedded home paths for on-screen display
- `SongDetailView` shows “Song notes (notes.txt)” when present
- `ArchiveDiagnosticsSelectedSongContext` + export line `selected_song_notes=`
- Fixture tests: Broken Folder `notes only`; Neon Hook has no notes line
- E2E smoke: `broken_folder_notes=notes only`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-18)

Index `notes.txt` sidecar text in scanner and fuzzy search (fixture: Broken Folder Example).

## Prior completed (music-18)

- `SidecarNotesReader` reads trimmed `notes.txt` at song folder root (read-only)
- `Song.sidecarNotes` populated during scan
- `MusicSearchMatchKind.songNote` with explainability label `song note`
- Search matches tokens in sidecar notes; haystack includes notes for fuzzy fallback
- Fixture tests: Broken Folder loads `notes only`, search `only` finds that song
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-17)

Fuzzy search: match scan warnings so operators can find problematic songs from diagnostic text.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Archive diagnostics UX: export skipped-entry lines in user-flow smoke or panel “copy diagnostics” affordance
- Search/index skipped-root labels (e.g. `LOOSE_FILE.txt`) for operator drill-down
