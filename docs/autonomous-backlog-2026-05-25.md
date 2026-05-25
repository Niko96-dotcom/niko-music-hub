# Autonomous backlog — 2026-05-25

## Picked (music-09)

Search tokenizer: split on whitespace/punctuation before normalizing so `neon hk` is two AND tokens, not `neonhk`.

## Completed

- `MusicSearchMatcher.tokens` splits query segments before `normalize`
- `matchDetails` requires every query token to match (true AND semantics)
- `MusicSearchIndexTests` cover token splitting and spaced-query AND behavior
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-08)

E2E/search smoke: assert search match explainability in `ArchiveUserFlowSmoke` and fixture smoke script.

## Prior (music-08 detail)

- `ArchiveUserFlowSmokeResult.searchMatchSummary` from `searchMatchSummaries` after fuzzy `neon hk` filter
- `ArchiveSmokeCommands` prints `search_match_summary=` and validates neon/hk tokens
- `script/e2e_user_smoke.sh` greps explainability markers
- `ArchiveUserFlowTests` asserts non-empty per-token summary on Neon Hook
- `docs/user-e2e.md` notes explainability in smoke assertions

## Prior (music-07)

Search match explainability: show per-token match reasons on song cards when a search filter is active.

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
- Optional: include search match summary in exported diagnostics text for support threads
