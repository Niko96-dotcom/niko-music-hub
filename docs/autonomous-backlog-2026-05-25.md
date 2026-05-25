# Autonomous backlog — 2026-05-25

## Picked (music-03)

Archive scan diagnostics: counts, warnings, root paths, latest scan time, skipped-at-root entries, redacted export to temp only.

## Completed

- `SkippedScanEntry` + `ScanResult.skippedEntries`; scanner records non-folders and invalid roots
- `ArchiveScanDiagnostics` + `ArchiveScanDiagnosticsBuilder` (UI-free core summary)
- `DiagnosticsPathRedactor` and `ArchiveDiagnosticsExporter` (blocks writes under archive roots)
- `ArchiveBrowserViewModel.scanDiagnostics`, export to temp, `ArchiveDiagnosticsPanelView`
- Fixture `LOOSE_FILE.txt` at archive root; tests for builder, redaction, export, VM, scanner
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full interactive app/user-flow coverage beyond fixture smoke hook
- Optional SwiftUI Accessibility drive only if needed; keep view-model smoke as primary gate
- Deeper per-folder skip reasons (hidden files inside song folders) if producers need them
