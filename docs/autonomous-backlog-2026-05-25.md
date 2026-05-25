# Autonomous backlog — 2026-05-25

## Picked (music-36)

Add fixture song where equal-score preview tiebreak is exercised in scan + export smoke.

## Completed (music-36)

- `Equal Score Tiebreak Lab` fixture: two mix WAVs with identical ranking signals and shared mtime; longer duration wins via duration tiebreak
- `PreviewConfidenceRankerTests.testEqualScoreTiebreakLabFixtureUsesDurationTiebreakCallout`
- `ArchiveDiagnosticsExporterTests.testFormattedTextIncludesEqualScoreTiebreakExportForTiebreakLab`
- E2E/smoke: `diagnostics_export_tiebreak_path` / `preview_rank_tiebreak=` assertions on exported diagnostics
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-35)

Surface when version/extension/duration tiebreak (not score bump) decided the main preview among equal-score candidates.

## Prior completed (music-35)

- `PreviewRankingDecidingFactor` + `PreviewConfidenceRanker.decidingFactor(winner:runnerUp:)`
- `PreviewRankingExplainability.tiebreakCallout` for version/extension/duration equal-score picks
- Main preview summary, diagnostics selected header, and `preview_rank_tiebreak=` export line
- Tests: `PreviewRankingTiebreakTests` (6 cases)
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: equal-score **version/extension** tiebreak in real scan is hard while those signals also bump score — consider decoupling score vs tiebreak in v0.2, or craft offset fixtures if product wants scan proof
