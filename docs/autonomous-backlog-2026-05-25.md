# Autonomous backlog — 2026-05-25

## Picked (music-43)

Fuzzy folder-name song search with explicit explainability and user-flow/E2E proof.

## Completed (music-43)

- `MusicSearchMatcher`: subsequence match on `originalFolderName` → `fuzzyFolderName` (score 18), label `fuzzy folder`
- Fixture query `brkn fld` finds Broken Folder Example without generic `fuzzy text` haystack
- Tests: `MusicSearchIndexTests`, `MusicSearchExplainabilityTests` (display title can differ from folder)
- User-flow + E2E: `folder_search_*`, `diagnostics_export_folder_*` markers and export file grep
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-42)

User-flow/E2E proof for `root_health_badge=` healthy omission and invalid-root panel/export parity.

## Prior completed (music-42)

- Healthy fixture smoke: export omits `root_health_badge=`; panel `rootHealthBadge` is nil
- Invalid-root smoke phase: fixture + missing temp root → export `root_health_badge=` matches panel badge (`1 invalid root · 1 root warning`)
- Shared `ArchiveDiagnosticsPanelAccessibility.rootHealthBadge` id wired in panel + smoke stdout
- Tests: `ArchiveUserFlowTests`; E2E: `healthy_export_omits_root_health_badge`, invalid-root export/panel cross-checks

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Fuzzy CPR/preview filename search (mirror folder fuzzy; lower priority than aliases)
- Preview ranking: equal-score **version/extension** tiebreak in real scan — decouple score vs tiebreak in v0.2 or offset fixtures
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
