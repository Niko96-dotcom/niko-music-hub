# Autonomous backlog — 2026-05-25

## Picked (music-39)

Surface pasteable support summary in diagnostics panel (parity with export `summary_line=`).

## Completed (music-39)

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

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: equal-score **version/extension** tiebreak in real scan is hard while those signals also bump score — consider decoupling score vs tiebreak in v0.2, or craft offset fixtures if product wants scan proof
- Archive diagnostics panel: add compact root-health badge when `globalWarnings` or invalid roots present (panel now has full support summary)
