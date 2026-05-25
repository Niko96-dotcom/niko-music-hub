# Autonomous backlog — 2026-05-25

## Picked (music-40)

Compact root-health badge in diagnostics panel when `globalWarnings` or invalid roots are present.

## Completed (music-40)

- `ArchiveDiagnosticsPanelContext.rootHealthBadge(for:)` — nil when healthy; compact counts for invalid roots and global warnings
- Panel header shows accent capsule badge (accessibility id `archive_diagnostics_root_health_badge`)
- Tests: `ArchiveDiagnosticsPanelContextTests` (healthy fixture, invalid root, plural, warnings-only), `ArchiveScanDiagnosticsBuilderTests`, `ArchiveBrowserViewModelTests`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-39)

Surface pasteable support summary in diagnostics panel (parity with export `summary_line=`).

## Prior completed (music-39)

- `ArchiveDiagnosticsPanelContext` — `supportSummaryLine` equals `exportSummaryLine` (redacted roots + scan counts)
- Panel shows selectable "Support summary" instead of shorter `summaryLine` only
- Tests: `ArchiveDiagnosticsPanelContextTests`, `ArchiveBrowserViewModelTests.testScanExposesDiagnosticsSummary`
- User-flow smoke + E2E: `diagnostics_panel_support_summary=` / `diagnostics_panel_matches_export=true`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-38)

Prove `summary_line=` pasteable scan export in user-flow smoke and E2E (completes music-37 follow-up).

## Prior completed (music-38)

- `ArchiveUserFlowSmoke` extracts and validates `summary_line=` from first diagnostics export (fixture: 5 songs, 1 warning, 2 skipped)
- Smoke stdout: `diagnostics_export_summary_match` / `diagnostics_export_summary_line=`
- E2E: `summary_line=` assertions on smoke log and `SEARCH_EXPORT_PATH`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate); optional: assert `archive_diagnostics_root_health_badge` on an invalid-root fixture path
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: equal-score **version/extension** tiebreak in real scan is hard while those signals also bump score — consider decoupling score vs tiebreak in v0.2, or craft offset fixtures if product wants scan proof
- Archive diagnostics export: mirror `root_health_badge=` in pasteable export for support tickets
