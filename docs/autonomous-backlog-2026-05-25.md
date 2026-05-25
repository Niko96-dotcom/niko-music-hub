# Autonomous backlog — 2026-05-25

## Picked (music-01)

Strengthen Archive Browser user-style verification: shared view-model smoke (`ArchiveUserFlowSmoke`), unit test for full fixture flow with write-probe and tree snapshot, E2E script assertions for scan/search/open evidence.

## Completed

- `ArchiveUserFlowSmoke` in `FeatureArchiveBrowser` — deterministic scan → search → select → dry-run open
- `ArchiveUserFlowTests` — fixture flow, write-probe denied, archive tree unchanged, dry-run CPR path
- `ArchiveSmokeCommands` — delegates to shared smoke (no duplicate scanner/opener path)
- `script/e2e_user_smoke.sh` — asserts `user_flow`, `search_matches=1`, `write_probe_denied`, `archive_unchanged`

## Next best TODO

- Richer archive diagnostics surface (warnings/counts/root state) for operators
- Preview ranking v0.2: version tiebreak, duration plausibility, extension tiebreak, explainability
- Optional SwiftUI Accessibility drive only if needed; keep view-model smoke as primary gate
