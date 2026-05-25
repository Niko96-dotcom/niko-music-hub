# Autonomous backlog — 2026-05-25

## Picked (music-07)

Search match explainability: show per-token match reasons on song cards when a search filter is active.

## Completed

- `MusicSearchResult` / `MusicSearchMatchDetail` with `matchSummary` (e.g. `neon → title start; hk → fuzzy title`)
- `MusicSearchIndex.searchResults(_:)` returns ranked results with explainability
- `ArchiveBrowserViewModel.searchMatchSummaries` + `SongCardView` hint line
- Tests: `MusicSearchExplainabilityTests`, extended `ArchiveBrowserViewModelTests`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-06)

Archive diagnostics UX: show scan summary and redacted archive roots in the sidebar diagnostics panel.

## Prior (music-05)

Search result ranking: sort matches by match quality (title > folder > filenames > fuzzy) instead of scan order.

## Prior (music-04)

Fuzzy song search: tokenized AND matching, diacritic/punctuation folding, subsequence typo tolerance; E2E smoke uses `neon hk` and asserts diagnostics counts.

## Prior (music-03)

Archive scan diagnostics: counts, warnings, root paths, latest scan time, skipped-at-root entries, redacted export to temp only.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias/note fields per SPEC §10 (no metadata layer yet)
- Deeper per-folder skip reasons inside song folders if operators need them
- Optional: surface search score/reasons in exported diagnostics for support threads
