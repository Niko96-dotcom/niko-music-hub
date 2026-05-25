# Autonomous backlog — 2026-05-25

## Picked (music-10)

Diagnostics export: include active search query and per-song match summaries when a filter is active.

## Completed

- `ArchiveDiagnosticsSearchContext` / `ArchiveDiagnosticsSearchMatch` for export-safe search snapshots
- `ArchiveDiagnosticsExporter` appends `active_search` section with query, match count, and per-title summaries
- `ArchiveBrowserViewModel.exportDiagnostics` passes `activeSearchExportContext()` from current filter state
- `ArchiveDiagnosticsExporterTests` + `ArchiveBrowserViewModelTests` cover formatted text and end-to-end export
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

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
- Preview ranking explainability in UI (ranker already emits `confidenceReasons`; surface in song detail)
