# Autonomous backlog — 2026-05-25

## Picked (music-47)

Diagnostics scan-health badge: surface song warnings and skipped-at-roots in panel + export when roots are otherwise valid.

## Completed (music-47)

- `ArchiveDiagnosticsPanelContext.rootHealthBadge`: includes song-warning and non-invalid skipped counts (no double-count with invalid roots)
- Tests: panel context, exporter, view-model, user-flow, E2E smoke markers for fixture badge parity
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-46)

Preview ranking: decouple version/extension from confidence score; prove equal-score version/extension tiebreak in real scan + user-flow/E2E.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
