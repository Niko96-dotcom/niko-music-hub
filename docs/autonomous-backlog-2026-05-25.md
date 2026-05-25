# Autonomous backlog — 2026-05-25

## Picked (music-44)

Fuzzy CPR/preview filename search with explicit explainability and user-flow/E2E proof.

## Completed (music-44)

- `MusicSearchMatcher`: subsequence on CPR/preview filenames → `fuzzyProjectVersionFileName` / `fuzzyPreviewFileName` (score 17), labels `fuzzy CPR file` / `fuzzy preview file`
- Fixture queries: `neohkv2` → Neon Hook; `v3 mx` → Preview Ranking Lab (no generic `fuzzy text`)
- Tests: `MusicSearchIndexTests`, `MusicSearchExplainabilityTests`
- User-flow + E2E: `cpr_search_*`, `preview_search_*`, diagnostics export grep
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-43)

Fuzzy folder-name song search with explicit explainability and user-flow/E2E proof.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: equal-score **version/extension** tiebreak in real scan — decouple score vs tiebreak in v0.2 or offset fixtures
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
