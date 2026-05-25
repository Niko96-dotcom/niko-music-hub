# Autonomous backlog — 2026-05-25

## Picked (music-37)

Fuzzy sidecar `notes.txt` search with dedicated explainability and user-flow/E2E proof.

## Completed (music-37)

- `MusicSearchMatchKind.fuzzySongNote` — subsequence match on sidecar notes before generic haystack fuzzy
- Tests: `MusicSearchExplainabilityTests`, `MusicSearchIndexTests.testFindsSongByFuzzySidecarNotesToken`
- User-flow smoke: query `nts nly` → Broken Folder Example + diagnostics export with `fuzzy song note`
- E2E: `notes_search_*` / `diagnostics_export_notes_*` assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-36)

Add fixture song where equal-score preview tiebreak is exercised in scan + export smoke.

## Prior completed (music-36)

- `Equal Score Tiebreak Lab` fixture: two mix WAVs with identical ranking signals and shared mtime; longer duration wins via duration tiebreak
- `PreviewConfidenceRankerTests.testEqualScoreTiebreakLabFixtureUsesDurationTiebreakCallout`
- `ArchiveDiagnosticsExporterTests.testFormattedTextIncludesEqualScoreTiebreakExportForTiebreakLab`
- E2E/smoke: `diagnostics_export_tiebreak_path` / `preview_rank_tiebreak=` assertions on exported diagnostics
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: equal-score **version/extension** tiebreak in real scan is hard while those signals also bump score — consider decoupling score vs tiebreak in v0.2, or craft offset fixtures if product wants scan proof
- Archive diagnostics: export scan `summary_line=` for support tickets (roots + warning/skipped counts in one pasteable line)
