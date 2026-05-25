# Autonomous backlog — 2026-05-25

## Picked (music-46)

Preview ranking: decouple version/extension from confidence score; prove equal-score version/extension tiebreak in real scan + user-flow/E2E.

## Completed (music-46)

- `PreviewConfidenceRanker`: version and extension affect tiebreak order only (not `confidenceScore`)
- Fixtures: `Equal Score Version Tiebreak`, `Equal Score Extension Tiebreak`; synced mtimes on `Preview Ranking Lab` v2/v3
- Tests: `PreviewConfidenceRankerTests`, `ArchiveDiagnosticsExporterTests`
- User-flow + E2E: version/extension tiebreak diagnostics export proof; fixture song count 7
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-45)

Fuzzy scan-warning search with explicit explainability and user-flow/E2E proof.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
