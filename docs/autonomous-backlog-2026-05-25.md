# Autonomous backlog — 2026-05-25

## Picked (music-05)

Search result ranking: sort matches by match quality (title > folder > filenames > fuzzy) instead of scan order.

## Completed

- `MusicSearchMatcher.matchScore` / per-token field-weighted scoring
- `MusicSearchIndex.search` sorts by score descending, then display title
- Tests: title beats filename-only; exact title token beats fuzzy subsequence
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-04)

Fuzzy song search: tokenized AND matching, diacritic/punctuation folding, subsequence typo tolerance; E2E smoke uses `neon hk` and asserts diagnostics counts.

## Prior (music-03)

Archive scan diagnostics: counts, warnings, root paths, latest scan time, skipped-at-root entries, redacted export to temp only.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias/note fields per SPEC §10 (no metadata layer yet)
- Deeper per-folder skip reasons inside song folders if operators need them
- Archive diagnostics UX: richer user-facing surface for warnings/counts/root state (export exists; UI thin)
