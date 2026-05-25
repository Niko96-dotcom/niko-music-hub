# Autonomous backlog — 2026-05-25

## Picked (music-15)

Diagnostics panel: redact embedded home paths in on-screen warnings, skipped labels/reasons, and song warning lines (export already covered in music-14).

## Completed

- `ArchiveScanDiagnostics.displayGlobalWarnings`, `displaySkippedEntries`, `displaySongWarningSummaries` mirror export redaction
- `ArchiveDiagnosticsPanelView` uses display helpers for warnings, skipped entries, and song summaries
- `ArchiveScanDiagnosticsTests` covers embedded CPR paths in panel-facing strings
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-14)

Diagnostics export: redact home-prefixed CPR/archive paths embedded in warning and skip-reason text.

## Prior completed (music-14)

- `DiagnosticsPathRedactor.redactPathsInText` scans free-form strings for embedded home paths
- Exporter applies redaction to `global_warning`, per-song `warning`, `selected_song_warning`, and skip `reason` lines
- `DiagnosticsPathRedactorTests` and `ArchiveDiagnosticsExporterTests` cover embedded CPR paths

## Prior (music-13)

Diagnostics export: include selected song CPR/warning summary alongside preview ranking when selected.

## Prior completed (music-13)

- `ArchiveDiagnosticsSelectedSongExplainability.cprSummary(for:)` for version count + latest CPR filename
- `ArchiveDiagnosticsSelectedSongContext` extended with `cprSummary`, `warningLines`, optional `mainPreviewSummary`
- `ArchiveDiagnosticsSelectedSongContext.from(song:)` builds export context without requiring a main preview
- Exporter writes `selected_song_cpr=` and `selected_song_warning=` lines under `selected_song`
- `ArchiveBrowserViewModel.selectedSongExportContext()` uses `.from(song:)` so Broken Folder exports CPR/warnings without previews
- `ArchiveDiagnosticsExporterTests`, `ArchiveDiagnosticsSelectedSongExplainabilityTests`, `ArchiveBrowserViewModelTests` coverage
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-12)

Diagnostics export: include selected song preview ranking summary and ranked preview lines when a song is selected.

## Prior (music-11)

Preview ranking explainability: human-readable main-preview summary and ranked alt list in song detail; E2E asserts Ranking Lab signals.

## Prior (music-10)

Diagnostics export: include active search query and per-song match summaries when a filter is active.

## Prior (music-09)

Search tokenizer: split on whitespace/punctuation before normalizing so `neon hk` is two AND tokens, not `neonhk`.

## Prior (music-08)

E2E/search smoke: assert search match explainability in `ArchiveUserFlowSmoke` and fixture smoke script.

## Prior (music-07)

Search match explainability: show per-token match reasons on song cards when a search filter is active.

## Prior (music-06)

Archive diagnostics UX: show scan summary and redacted archive roots in the sidebar diagnostics panel.

## Prior (music-05)

Search result ranking: sort matches by match quality (title > folder > filenames > fuzzy) instead of scan order.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias/note fields per SPEC §10 (no metadata layer yet)
- Song detail / search cards: redact embedded paths in per-song `scanWarnings` when shown in UI (if any surface raw paths)
