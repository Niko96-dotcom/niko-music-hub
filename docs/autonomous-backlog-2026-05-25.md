# Autonomous backlog — 2026-05-25

## Picked (music-35)

Surface when version/extension/duration tiebreak (not score bump) decided the main preview among equal-score candidates.

## Completed (music-35)

- `PreviewRankingDecidingFactor` + `PreviewConfidenceRanker.decidingFactor(winner:runnerUp:)`
- `PreviewRankingExplainability.tiebreakCallout` for version/extension/duration equal-score picks
- Main preview summary, diagnostics selected header, and `preview_rank_tiebreak=` export line
- Tests: `PreviewRankingTiebreakTests` (6 cases)
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-34)

Stronger preview-ranking duration explainability in UI/export (show actual seconds) plus version-parser edge-case tests (v10 vs v2, separators).

## Prior completed (music-34)

- `PreviewRankingExplainability` appends formatted duration to duration signals (`too short (5s)`, `plausible length (3:30)`)
- `PreviewFilenameParserTests` lock multi-digit version parsing and separator edge cases
- `PreviewConfidenceRankerTests.testMultiDigitVersionBeatsLowerVersionWhenRoleAndFolderMatch`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-33)

Surface per-song too-short preview breakdown inline in the archive diagnostics panel (was export-only after music-32).

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: add fixture song where equal-score version/extension tiebreak is exercised in scan + export smoke
