# Autonomous backlog — 2026-05-25

## Picked (music-18)

Index `notes.txt` sidecar text in scanner and fuzzy search (fixture: Broken Folder Example).

## Completed (music-18)

- `SidecarNotesReader` reads trimmed `notes.txt` at song folder root (read-only)
- `Song.sidecarNotes` populated during scan
- `MusicSearchMatchKind.songNote` with explainability label `song note`
- Search matches tokens in sidecar notes; haystack includes notes for fuzzy fallback
- Fixture tests: Broken Folder loads `notes only`, search `only` finds that song
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-17)

Fuzzy search: match scan warnings so operators can find problematic songs from diagnostic text.

## Prior completed (music-17)

- `MusicSearchMatchKind.scanWarning` with explainability label `scan warning`
- `MusicSearchMatcher` matches tokens against `song.scanWarnings` and includes warnings in fuzzy haystack
- Fixture test finds Broken Folder Example via `project` in “No CPR project files found”
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-16)

Song detail / search cards: surface per-song `scanWarnings` with embedded home-path redaction; redact dry-run CPR path in song detail.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Surface `sidecarNotes` in song detail UI (read-only)
- Redact dry-run CPR paths in smoke stdout/logs when archive roots live under home (optional polish)
