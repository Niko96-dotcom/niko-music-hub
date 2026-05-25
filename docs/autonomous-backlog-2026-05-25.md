# Autonomous backlog — 2026-05-25

## Picked (music-53)

Diagnostics panel: dedicated preview tiebreak callout when a song is selected (export `preview_rank_tiebreak=` parity) and user-flow/E2E proof that panel selected header + callout match export on the duration tiebreak fixture.

## Completed (music-53)

- `ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for:)`
- `ArchiveDiagnosticsPanelView` shows accent tiebreak line; accessibility id `archive_diagnostics_preview_tiebreak_callout`
- Removed duplicate tiebreak text in `selectedSongHeader` (already embedded in `mainPreviewSummary`)
- User-flow smoke + E2E: `diagnostics_panel_duration_tiebreak_*_match=` markers
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-52)

Diagnostics panel: surface support-summary truncation footnote when many songs have warnings (export metadata existed; in-app panel had no operator hint).

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
