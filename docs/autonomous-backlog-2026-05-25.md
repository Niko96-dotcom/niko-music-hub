# Autonomous backlog — 2026-05-25

## Picked (music-49)

Diagnostics: cap/truncate song warning titles in pasteable `summary_line=` when many songs have warnings.

## Completed (music-49)

- `ArchiveScanDiagnostics.summaryLineMaxSongWarningTitles = 5`
- `formattedSongWarningTitles` appends `and N more` after five sorted titles
- Tests: `testSummaryLineTruncatesManySongWarningTitles` (TDD red → green)
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-48)

Support summary line: include sorted song warning titles in pasteable `summary_line=` / panel support summary when warnings exist.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
- Diagnostics: document truncation cap in `docs/user-e2e.md` / operator guide when many warnings
