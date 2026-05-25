# Autonomous backlog — 2026-05-25

## Picked (music-16)

Song detail / search cards: surface per-song `scanWarnings` with embedded home-path redaction; redact dry-run CPR path in song detail.

## Completed

- `Song.displayScanWarnings` and `Song.displayDryRunPath` centralize UI-safe warning/path strings
- `SongDetailView` shows scan warnings and redacted dry-run CPR path
- `SongCardView` shows first redacted warning on browse cards
- `ArchiveUserFlowSmoke` + E2E assert Broken Folder display warnings include CPR signal
- `SongDisplayTests` cover path redaction helpers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-15)

Diagnostics panel: redact embedded home paths in on-screen warnings, skipped labels/reasons, and song warning lines (export already covered in music-14).

## Prior completed (music-15)

- `ArchiveScanDiagnostics.displayGlobalWarnings`, `displaySkippedEntries`, `displaySongWarningSummaries` mirror export redaction
- `ArchiveDiagnosticsPanelView` uses display helpers for warnings, skipped entries, and song summaries
- `ArchiveScanDiagnosticsTests` covers embedded CPR paths in panel-facing strings
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-14)

Diagnostics export: redact home-prefixed CPR/archive paths embedded in warning and skip-reason text.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias/note fields per SPEC §10 (no metadata layer yet)
- Redact dry-run CPR paths in smoke stdout/logs when fixture roots live under home (optional polish)
