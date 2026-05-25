# Autonomous backlog — 2026-05-25

## Picked (music-48)

Support summary line: include sorted song warning titles in pasteable `summary_line=` / panel support summary when warnings exist.

## Completed (music-48)

- `ArchiveScanDiagnostics.summaryLine` appends ` — Title A, Title B` after warning counts (sorted, from `songWarningSummaries`)
- Tests: `ArchiveScanDiagnosticsTests`, panel context fixture parity, exporter, user-flow, E2E smoke markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-47)

Diagnostics scan-health badge: surface song warnings and skipped-at-roots in panel + export when roots are otherwise valid.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
- Diagnostics: optional cap/truncation when many songs have warnings (large real archives)
