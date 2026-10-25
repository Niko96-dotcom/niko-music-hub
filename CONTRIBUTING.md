# Contributing

Niko Music Hub is a native macOS SwiftUI app (Swift 6, SwiftPM). Keep product code in Swift and keep archive
access read-only by default. This page is the way in; it links to the detail instead of repeating it.

## Reading order

1. **Build and run.** `./script/dev.sh doctor` checks this Mac; `./script/dev.sh run` builds
   `dist/NikoMusicHub.app` and opens it. More commands and startup logs: [docs/local-dev-flow.md](docs/local-dev-flow.md).
2. **The map.** [docs/architecture-map.md](docs/architecture-map.md): entry points, modules, main flows, state
   owners, seams and gates, on one page.
3. **The rules.** The table in [AGENTS.md](AGENTS.md#rules-and-what-enforces-them): each rule, what enforces it
   and the doc that explains it. It is written for agents and people alike.
4. **The UI contract.** [docs/design-contract.md](docs/design-contract.md), before you touch a SwiftUI view.
5. **The gates** below, before you call a change done. Everything else: [docs/README.md](docs/README.md).

## Gates

```bash
./script/ci.sh              # link check, clean strict build, all tests, self-tests, release-script tests
./script/e2e_user_smoke.sh  # drives the real app through the fixture archive
./script/dev.sh check       # both, plus a disposable startup check
```

- `ci.sh` builds into an empty scratch path and fails on any warning the build prints, except SwiftPM's
  notices about a pinned dependency (`warning: 'sparkle': skipping cache due to an error` when two SwiftPM
  processes share the package cache). Compiler, manifest, driver and linker warnings always fail it.
- `ci.sh` skips host-only CoreAudio capture tests that need a usable system-audio capture device. Those tests
  stay in the source suite; they are just not the always-on local gate.
- Run `ci.sh` from an ordinary Terminal window. In a background or low-priority shell, four recorder probe
  timing tests (`SystemAudioCapturePermissionProbeTests`, `SystemAudioTapInputLayoutTests`) can fail on
  unchanged code.
- The E2E smoke needs Accessibility and Screen Recording for the terminal that runs it; see
  [docs/user-e2e.md](docs/user-e2e.md).
- A release adds the exact-commit acceptance record: [docs/release.md](docs/release.md).

Where the output lands:

| Gate | Log and evidence |
| --- | --- |
| `./script/ci.sh` | stdout only; redirect it (`./script/ci.sh > ci.log 2>&1`) to keep it |
| `./script/e2e_user_smoke.sh` | `.build/e2e-smoke.log`, `.build/e2e-public-ui.{log,txt,png}` |
| `./script/dev.sh check`, `startup` | `.build/dev-flow/` (one log per stage; `startup.XXXXXX/` holds stdout, stderr, window and accessibility dumps) |
| `./script/capture_window_proof.sh` | `dist/window-visible-proof.png`, `dist/desktop-proof.png` |
| `script/release-all.sh` | `dist/release/` (artifacts, manifests, notary logs) |

Window proof and accessibility dumps use `script/ui_probe.swift` (CoreGraphics window matching plus
ApplicationServices AX).

## Rule tests

The test target `RepoRuleTests` (`Tests/RepoRuleTests/`) reads the source text and checks the repository's
rules that the compiler cannot: who may build a guard, which strings a view may show,
which module may import which. They check rules, not behavior. Each one exists because the same mistake
shipped more than once.

When one fails:

1. Read its message and the test's doc comment: it names the rule and the file and line it found.
2. Follow the link to the [AGENTS.md](AGENTS.md#rules-and-what-enforces-them) row and its doc for the why.
3. Fix the code, not the check. Change a check only when the rule itself changes, and then change its
   doc in the same commit. Lists of allowed exceptions in a test carry a reason per entry; add one only
   with a reason.

## Where to look when something breaks

| Flow | Start here |
| --- | --- |
| Launch | `NikoMusicHubMain` and `AppComposition.make()` ([map § Launch](docs/architecture-map.md#launch)); startup logs from `./script/dev.sh startup` |
| Archive scan | `ArchiveScanOrchestrator`, `MusicArchiveScanner` ([map § Find a song](docs/architecture-map.md#find-a-song-and-open-its-project)); the in-app diagnostics panel and `swift run NikoMusicHubCLI export-diagnostics` |
| Tool run | the tool's view model and `ToolOutputDestination` ([map § Run a tool](docs/architecture-map.md#run-a-tool-and-deliver-its-output), [architecture § tool work](docs/architecture.md#how-a-tool-runs-its-work)) |
| Project Vault | `ProjectVaultOperationCoordinator`, `LiveProjectVaultRuntime`, the transfer journal ([map § Project Vault](docs/architecture-map.md#project-vault-archive-restore-recover), [vault-durability.md](docs/vault-durability.md)) |
| Quit | `HubTerminationCoordinator` ([ADR 019](docs/decisions/019-running-work-and-quit.md)) |
| Release | the failing gate's message in `script/release-all.sh` output ([release.md](docs/release.md), [release-validation.md](docs/release-validation.md)) |

## Git hygiene

- Keep commits coherent and green.
- Do not commit `.ai/runs/`, `.build/`, `dist/`, `DerivedData/`, `.DS_Store`, `.xcresult`, or personal scan logs.
- Do not push unless the current task explicitly asks for it.
- GitHub Actions are not required; paste local gate results into PRs instead.
