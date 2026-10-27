# Documentation index

Every live document, with when to read it. A live document describes current behavior, a current rule
or a current process, and changes in the same commit as the behavior it describes. Dated records
(audits, benchmark reports, acceptance evidence, superseded plans) are in [history/](history/README.md).
`script/check-doc-links.py` (run by `./script/ci.sh`) fails on a broken relative link or anchor.

New to the code? Read [CONTRIBUTING.md](../CONTRIBUTING.md) first: it gives the reading order.

## Build and run

- [../CONTRIBUTING.md](../CONTRIBUTING.md): read it first. Reading order, gates, what a failing rule test means, where to look when something breaks.
- [local-dev-flow.md](local-dev-flow.md): read it when you build, run or check the app with `script/dev.sh`, or need startup logs.
- [user-e2e.md](user-e2e.md): read it when `script/e2e_user_smoke.sh` fails or you change what it drives.
- [../Fixtures/CubaseArchive/README.md](../Fixtures/CubaseArchive/README.md): read it when you change the synthetic test archive.
- [install.md](install.md): read it when you install a release or change the first-launch Set Up.

## Architecture and rules

- [architecture-map.md](architecture-map.md): read it before a structural change. Entry points, modules, main flows, state owners, seams, gates, gaps, open questions.
- [architecture.md](architecture.md): read it when you change an owner the map names; it holds the ownership detail and the safety rules.
- [../AGENTS.md](../AGENTS.md): read it before any change. The rules and what enforces each one.
- [de-slop.md](de-slop.md): read it only when someone asks for the Ultimate De-Slop loop.

## UI contract

- [design-contract.md](design-contract.md): read it before you touch a SwiftUI view. Binding; guarded by the design rule tests.

## Tools and archive behavior

- [preview-selection.md](preview-selection.md): read it when you change preview ranking, card titles or the persistent player's selection.
- [bpm-tapper-algorithm.md](bpm-tapper-algorithm.md): read it when you change `TempoEstimator`.
- [menu-bar-quick-access.md](menu-bar-quick-access.md): read it when you change the menu bar extra or the Dock menu.
- [user-guide-stem-separation.md](user-guide-stem-separation.md): read it when you change Stem Separation as a user sees it.

## Project Vault

- [vault-durability.md](vault-durability.md): read it before you change how a Vault copy is proved durable or when the Active copy may go.
- [vault-recovery.md](vault-recovery.md): read it when you change the recovery copy export or import.
- [ableton-and-project-restore.md](ableton-and-project-restore.md): read it when you change song folders, Ableton support, archive or restore as a user sees them.
- [linked-archive-restore.md](linked-archive-restore.md): read it when you change Restore & Open for a linked historical archive.

## Release and acceptance

- [release.md](release.md): read it before a release. The fail-closed local release pipeline.
- [release-validation.md](release-validation.md): read it when you run the release commands on the release machine.
- [release-checklist.md](release-checklist.md): tick it during a release.
- [ai-acceptance-testing.md](ai-acceptance-testing.md): read it when you produce or review the exact-commit acceptance record.
- [update-feed.md](update-feed.md): read it when you change Sparkle, the update feed or its signing.
- [source-sale.md](source-sale.md): read it when you produce a buyer source export.
- [../Niko-Music-Hub-threat-model.md](../Niko-Music-Hub-threat-model.md): read it when you change a trust boundary (updates, helpers, media parsing, Vault removal). Baseline 2026-09-19.
- [../CHANGELOG.md](../CHANGELOG.md), [../SOURCE_PROVENANCE.md](../SOURCE_PROVENANCE.md), [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md): release records the release scripts validate.

## Decisions

- [decisions/017-stem-separation-backend.md](decisions/017-stem-separation-backend.md): read it when you add or change a stem backend.
- [decisions/018-codex-chrome-material.md](decisions/018-codex-chrome-material.md): read it before you change the chrome material.
- [decisions/019-running-work-and-quit.md](decisions/019-running-work-and-quit.md): read it when you add work that quit must wait for.
- [decisions/020-module-boundary-checks.md](decisions/020-module-boundary-checks.md): read it when you add a module or a module edge.
- [decisions/021-keep-local-pin-format.md](decisions/021-keep-local-pin-format.md): read it when you touch Keep Local pins.
- [decisions/022-appcore-scope-and-vault-runtime-target.md](decisions/022-appcore-scope-and-vault-runtime-target.md): read it when you decide whether code belongs in `AppCore`.
- [decisions/023-pinned-helper-downloads.md](decisions/023-pinned-helper-downloads.md): read it when you change a helper download or make new helper pins.

## Reference

- [reference/stem-separation-contract.md](reference/stem-separation-contract.md): read it when you implement a second stem backend.
- [reference/cubase-file-orga/PROJECT.md](reference/cubase-file-orga/PROJECT.md), [SPEC.md](reference/cubase-file-orga/SPEC.md), [DESIGN_SYSTEM.md](reference/cubase-file-orga/DESIGN_SYSTEM.md): the archive browser this app ported; read them for the origin of an archive rule, not for current UI.

## History

- [history/README.md](history/README.md): dated records, one line per file. Not maintained; do not implement from them.
