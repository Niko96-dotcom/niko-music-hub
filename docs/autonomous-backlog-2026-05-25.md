# Autonomous backlog — 2026-05-25

## Picked (music-04)

Fuzzy song search: tokenized AND matching, diacritic/punctuation folding, subsequence typo tolerance; E2E smoke uses `neon hk` and asserts diagnostics counts.

## Completed

- `MusicSearchMatcher` (normalize, tokenize, subsequence fuzzy per token)
- `MusicSearchIndex` wired to matcher; fixture + synthetic tests
- `ArchiveUserFlowSmoke` uses fuzzy query `neon hk`; exports `diagnostics_songs` / `diagnostics_skipped`
- `e2e_user_smoke.sh` greps fuzzy query + diagnostics markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-03)

Archive scan diagnostics: counts, warnings, root paths, latest scan time, skipped-at-root entries, redacted export to temp only.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias/note fields per SPEC §10 (no metadata layer yet)
- Deeper per-folder skip reasons inside song folders if operators need them
- Optional: rank search results by match quality instead of scan order
