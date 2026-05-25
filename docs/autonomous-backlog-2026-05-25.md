# Autonomous backlog — 2026-05-25

## Picked (music-19)

Surface `sidecarNotes` in song detail UI and diagnostics export (read-only).

## Completed (music-19)

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
- Preview ranking v0.2: parsed version tiebreak, duration plausibility, extension tiebreak (subset remains in ranker)
- Redact dry-run CPR paths in smoke stdout/logs when archive roots live under home (optional polish)
