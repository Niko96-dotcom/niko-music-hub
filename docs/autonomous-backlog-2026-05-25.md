# Autonomous backlog — 2026-05-25

## Picked (music-42)

User-flow/E2E proof for `root_health_badge=` healthy omission and invalid-root panel/export parity.

## Completed (music-42)

- Healthy fixture smoke: export omits `root_health_badge=`; panel `rootHealthBadge` is nil
- Invalid-root smoke phase: fixture + missing temp root → export `root_health_badge=` matches panel badge (`1 invalid root · 1 root warning`)
- Shared `ArchiveDiagnosticsPanelAccessibility.rootHealthBadge` id wired in panel + smoke stdout
- Tests: `ArchiveUserFlowTests`; E2E: `healthy_export_omits_root_health_badge`, invalid-root export/panel cross-checks
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-41)

Mirror `root_health_badge=` in pasteable diagnostics export (parity with panel badge).

## Prior completed (music-41)

- `ArchiveDiagnosticsExporter.formattedText` emits `root_health_badge=` when `ArchiveDiagnosticsPanelContext.rootHealthBadge(for:)` is non-nil; omitted when healthy
- Tests: `ArchiveDiagnosticsExporterTests` (healthy fixture omits line; invalid-root scan includes badge text)
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- Preview ranking: equal-score **version/extension** tiebreak in real scan is hard while those signals also bump score — consider decoupling score vs tiebreak in v0.2, or craft offset fixtures if product wants scan proof
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate; panel badge id is now smoke-proven)
