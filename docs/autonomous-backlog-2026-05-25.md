# Autonomous backlog — 2026-05-25

## Picked (music-45)

Fuzzy scan-warning search with explicit explainability and user-flow/E2E proof.

## Completed (music-45)

- `MusicSearchMatcher`: subsequence on scan warnings → `fuzzyScanWarning` (score 19), label `fuzzy scan warning`
- Matcher order: exact scan warning → sidecar notes (exact/fuzzy) → fuzzy scan warning (avoids stealing `nts`-style note tokens)
- Fixture query: `ncpr fnd` → Broken Folder Example warning "No CPR project files found"
- Tests: `MusicSearchIndexTests`, `MusicSearchExplainabilityTests`
- User-flow + E2E: `fuzzy_warning_search_*`, diagnostics export grep
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-44)

Fuzzy CPR/preview filename search with explicit explainability and user-flow/E2E proof.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: equal-score **version/extension** tiebreak in real scan — decouple score vs tiebreak in v0.2 or offset fixtures
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
