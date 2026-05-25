# Autonomous backlog — 2026-05-25

## Picked (music-51)

E2E/user-flow proof of `summary_line` song-title truncation when many songs have warnings (unit tests existed; fixture smoke did not).

## Completed (music-51)

- `Fixtures/CubaseArchiveSummaryTruncation/` — eight CPR-less songs for deterministic truncation lab
- `ArchiveUserFlowSmoke` scans truncation lab in isolation and asserts export `summary_line` + metadata
- `ArchiveScanDiagnosticsSummaryTruncationFixtureTests` (core scan/builder)
- E2E: `diagnostics_export_summary_truncation_*` markers and export file assertions
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-50)

Diagnostics: export explicit truncation metadata when `summary_line` omits song warning titles beyond the cap.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
