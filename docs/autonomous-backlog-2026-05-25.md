# Autonomous backlog — 2026-05-25

## Picked (music-52)

Diagnostics panel: surface support-summary truncation footnote when many songs have warnings (export metadata existed; in-app panel had no operator hint).

## Completed (music-52)

- `ArchiveScanDiagnostics.summaryLineSongWarningTitlesTruncationFootnote` + `ArchiveDiagnosticsPanelContext.supportSummaryTruncationFootnote`
- `ArchiveDiagnosticsPanelView` shows footnote under **Support summary** when truncated
- User-flow smoke + E2E: `diagnostics_panel_summary_truncation_footnote_*` markers on truncation lab
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-51)

E2E/user-flow proof of `summary_line` song-title truncation when many songs have warnings (unit tests existed; fixture smoke did not).

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
