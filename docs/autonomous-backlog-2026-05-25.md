# Autonomous backlog — 2026-05-25

## Picked (music-11)

Preview ranking explainability: human-readable main-preview summary and ranked alt list in song detail; E2E asserts Ranking Lab signals.

## Completed

- `PreviewRankingExplainability` maps `confidenceReasons` to readable labels (omits `recency`)
- `SongDetailView` shows main preview summary and ranked alt previews when multiple candidates exist
- `ArchiveUserFlowSmoke` + E2E script assert `preview_rank_summary` includes v3/wav for Preview Ranking Lab
- `PreviewRankingExplainabilityTests`, `ArchiveBrowserViewModelTests`, `ArchiveUserFlowTests` coverage
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

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
- Include preview ranking summary in diagnostics export when a song is selected
