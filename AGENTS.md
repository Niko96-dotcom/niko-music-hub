# Niko Music Hub — Agent Rules

The one rulebook, for agents and people. Reading order: [CONTRIBUTING.md](CONTRIBUTING.md). All docs: [docs/README.md](docs/README.md).

## Mission

**Niko Music Hub** is a shipped native macOS SwiftUI app (current release version: `VERSION`) that combines
the outside-Cubase production tools with a Cubase archive browser and Project Vault.

The app is built. Work on it as a maintained product: extend and harden existing modules rather than
re-bootstrapping. Do not embed Electron/React/TypeScript/Python runtime code into the product — port
behavior into Swift modules instead.

## Product boundaries

- Native macOS app, Swift 6.x, SwiftUI + AppKit interop where useful.
- Local-first and read-only toward real music archives by default.
- Never rename, move, delete, or rewrite real Cubase/music files outside an explicit,
  user-confirmed Project Vault transfer.
- Tests that touch archives must use fixtures; never exercise destructive cases on real music data.
- User-style E2E (`./script/e2e_user_smoke.sh`) is mandatory before any release.
- GitHub Actions are intentionally not configured; local gates are the source of truth.

## Architecture

- `NikoMusicCore`: pure Swift domain/scanning/search/opening safety, SQLite persistence and the Project Vault
  engines. No SwiftUI, no AppKit UI.
- `AppCore`: only the shell kit (tool registry, context, settings, jobs and quit, output inbox, diagnostics,
  shared components, helper tools). A subsystem with its own state owners and rules, used only by one feature
  and the composition, gets its own target over `AppCore`, as `ProjectVaultRuntime` did (ADR 022).
- `FeatureArchiveBrowser`: SwiftUI feature behind the same `ToolFeature` boundary as the other tools.
- Feature modules stay independent: `FeatureBPMTapper`, `FeatureAudioConverter`, `FeatureAudioRecorder`,
  `FeatureDownloader`, `FeatureStemSeparation`. The one documented exception is Stem Separation → Downloader.
- App target is `NikoMusicHub`; bundle identity is fixed in `BUNDLE_ID`.

Start with `docs/architecture-map.md`: entry points, main flows, state owners, seams, gates, where the code
differs from these rules, and open questions. Detail: `docs/architecture.md`. UI: `docs/design-contract.md`
(binding; read it before touching any SwiftUI view). Decisions: `docs/decisions/`. Reference material:
`docs/reference/`. Records in `docs/history/` (the superseded UI plan, the v0.1 scope, audits, benchmarks)
are not maintained: do **not** implement from them.

## Engineering baseline

Priorities: maintainability, readability, clear responsibilities, and straightforward code a new developer
can follow. Read `docs/architecture-map.md` before a structural change. When two rules below pull apart,
pick the design that leaves the reader less to hold in mind.

- **Keep related knowledge and invariants together.** Each rule and each piece of state has one owner (the
  map's state-owner table). Put the check, its comment and its test with that owner, not in every caller:
  output admission is only `ToolOutputGuard`, the Vault queue is only `ProjectVaultOperationCoordinator`.
- **Make dependencies and control flow explicit.** Pass collaborators in through an initializer,
  `ToolContext` or a host struct, and wire them in `AppComposition.make()`. Do not add `.shared` singletons,
  `ProcessInfo` reads outside `MusicHubRuntimeEnvironment`, or `NotificationCenter` routing. Remove an
  ordering constraint, or name it in the interface and test it.
- **Require abstractions to reduce the reader's total mental workload.** A new protocol, wrapper,
  coordinator, extension file or option must hide more than it adds. A protocol earns its place with two
  adapters (production and test), as `WorkspaceOpening` and `ArchiveRootWatching` have. No pass-through
  layers.
- **Split by responsibility, not by file or function size.** Extract an owner when a set of state and rules
  can be understood on its own, as `ArchiveMetadataEditingCoordinator` was. Do not cut a type into more
  `+Extension.swift` files or helpers only to make it shorter: that adds jumps and keeps the shared state.
- **Respect Swift's idioms and the project's constraints.** Swift 6 concurrency (`@MainActor` view models,
  actors for shared mutable state, `Sendable` values), value types and enums over flags, `throws` for a
  refusal, the SwiftUI state rules, no warnings, the module edges of ADR 020, local-first and read-only
  toward music archives.

## Rules and what enforces them

Each rule exists because agents broke it more than once. Prefer the enforcer over this table: if a change
trips one, fix the code, not the check. When the operator corrects a mistake, fix it and add its rule here.
A rule that is already listed with "judgment" next to it is a repeat: enforce it in the same change
(architecture, then types, then a test that names the right file or function). Drop a row once its mistake
cannot compile. Rule tests live in `Tests/RepoRuleTests/`; a test in another target names it.

| Rule | Enforced by | Doc |
| --- | --- | --- |
| **Count copy.** Every count in a string goes through `CountCopy.count` / `CountCopy.noun` (NikoMusicCore) — never `"\(n) songs"` or `n == 1 ? "song" : "songs"` | `CountCopySourceTests.testNoRawCountBeforeAPluralNounUnderSources` (all of Sources/) | `Sources/NikoMusicCore/Domain/CountCopy.swift` |
| **No warnings.** No compiler warnings, in any configuration | `strictSwiftSettings` (`-warnings-as-errors`) on every target: `PackageSettingsSourceTests.testEveryTargetBuildsWithWarningsAsErrors`. The flag cannot promote a warning Swift downgraded itself (a call into isolation inferred from a `@preconcurrency` protocol such as SwiftUI's `View`), so `./script/ci.sh` builds clean and fails on any printed warning but SwiftPM's pinned-dependency notices: `.testCIFailsOnAnyWarningInACleanBuild` | [CONTRIBUTING](CONTRIBUTING.md#gates) |
| **Commit outcome.** A caller that registers Undo/Redo, queues Vault work or reports success branches on `MetadataCommitOutcome`; `_ =` only for a plain edit whose refusal reports its own warning | The outcome is not `@discardableResult` and warnings fail the build; `ArchiveMetadataEditingOwnerTests` (FeatureArchiveBrowserTests) | [architecture § metadata editing](docs/architecture.md#archive-metadata-editing-ownership) |
| **Real defaults.** Only `AppComposition.makeUserDefaults` picks the person's real defaults; tests, previews and harnesses use `InMemoryPreferenceStore` or `UserDefaults(suiteName:)` | Store initializers have no `.standard` default; `RealUserDefaultsSourceTests.testOnlyTheCompositionRootReadsRealUserDefaults` | [map § state owners](docs/architecture-map.md#state-owners-observed) |
| **Isolated launches.** UI fixture launches also isolate AppKit preferences with a disposable bundle ID and an embedded settings suite; a suite alone is insufficient | `IsolatedAppLaunch` runs before SwiftUI; `IsolatedAppLaunchTests` (AppCoreTests); `E2ESmokeIsolationSourceTests`, `LocalExternalProofHarnessSourceTests`; E2E compares the full production preferences domain | [local-dev-flow](docs/local-dev-flow.md), [user-e2e](docs/user-e2e.md) |
| **Output admission.** A tool run gets its output folder and guard from one `ToolOutputDestination.load(from:)`; other folder checks use `ToolOutputGuard(settings:)`; the archive browser's exports and New Song use `writeProtectedRoots()`; never the browse list, never `[]` | `ToolOutputGuard` is the only app-side root list (`outputProtectedRoots` is internal); no "protect nothing" defaults; `OutputGuardSourceTests.testOnlyToolOutputGuardUsesOutputWriteGuard`, `.testToolRunsGetTheirGuardFromToolOutputDestination` (builders listed with reasons), `.testNoWriterPassesTheBrowseListOrNothingAsProtection` | [architecture § Safety](docs/architecture.md#safety-architecture) |
| **Settings for a write.** Settings that gate a write or a Project Vault decision are loaded with `try`, and the action is refused when it throws; display-only code reads `ToolContext.appSettings` | `OutputGuardSourceTests.testNoNewTryOptionalSettingsLoads` (per-file list of the `try? …loadSettings()` sites that stay, each with its reason) | [architecture § Safety](docs/architecture.md#safety-architecture) |
| **Keep Local pins.** Checked, written and removed only through `VaultSettings.keepLocalPins` (`KeepLocalPins`); never build a key set of IDs and path spellings | `keepLocalProjectIDs` is internal to AppCore; `KeepLocalPinsSourceTests.testOnlyTheOwnersTouchTheRawKeepLocalSet` | [ADR 021](docs/decisions/021-keep-local-pin-format.md) |
| **Recent outputs.** A tool page reads its recent outputs only through `ToolRecentOutputs` (AppCore); feature modules never call `listItems()` or observe `.outputInboxDidChange` | `HandoffSurfacingSourceTests.testFeatureModulesReadRecentOutputsOnlyThroughToolRecentOutputs` | [architecture § recent outputs](docs/architecture.md#tool-recent-outputs) |
| **Tool runs.** Work the person waits for is a `JobRunner` job (`ToolContext.jobRunner.enqueue`); a tool's own `Task` is only view-local async or a step its job or take awaits and cancels; work outside the runner registers by hand as a named `ShellJobExtraSourceID` exception | `ShellJobExtraSourceID` is a closed enum, so `setExtraJob(sourceID:)` takes no other source; `ToolWorkSourceTests.testEveryTaskInAToolIsListedWithItsReason`, `.testExtraSourcesAreTheNamedExceptions` | [architecture § tool work](docs/architecture.md#how-a-tool-runs-its-work) |
| **Running work and quit.** Work that must not be cut off registers with `ShellJobStatusCenter`; quit asks `HubTerminationCoordinator`; the delegate reaps helper process groups; only the composition builds the process runner and its registry | `HubTerminationSourceTests` (3); `HubTerminationCoordinatorTests`, `ShellJobStatusCenterTests` (AppCoreTests) | [ADR 019](docs/decisions/019-running-work-and-quit.md) |
| **Injected helpers.** Only the composition builds the helper probe and locator and the one `ToolContext`; the locator reads no process environment; helpers run without a shell | `HelperToolSourceTests` (3), `ToolContextSourceTests.testCompositionBuildsOneContextAndHandsLaunchWarningsToTheShell` | [architecture § Helper tools](docs/architecture.md#helper-tools) |
| **Archive page.** Archive views state intent (`openSongDetail`, `showBoard`, `setBrowseLayout(list:)`, `showAnalytics`, `clearSelection`, …); only `ArchivePageModel` writes `viewMode` and `listShowsDetail`; the detail's status menu uses the status gate | The compiler: both setters are `private(set)` in `ArchivePageModel`; `ArchiveViewIntentSourceTests.testOnlyThePageModelWritesThePage`, `.testSongDetailStatusMenuUsesTheStatusGate` | [architecture § Archive page state](docs/architecture.md#archive-page-state) |
| **Vault records.** A transfer's state and a restore's phase change only in the engines' checked `checkAndSave` and the store's reconcile; Vault folder names come only from `VaultFolders` | `VaultStateWriterSourceTests.testOnlyTheCheckedWritesAssignAState`, `VaultFoldersSourceTests.testOnlyVaultFoldersSpellsTheFolderNames` | [architecture § Vault state changes](docs/architecture.md#vault-state-changes), [§ Vault folders](docs/architecture.md#vault-folders) |
| **Automatic archiving.** The copy-only Done copy is the only automatic archiving; Settings offers no background archiving and no Vault login item; Settings saves the scan list and the archive follows the store | `SettingsLiquidSourceTests.testVaultSettingsOfferNoBackgroundArchivingAndNoLoginItem`, `.testSettingsAndSetUpNeverReachIntoTheArchiveViewModel` | [map gap 8](docs/architecture-map.md#where-the-code-differs-from-the-intent-observed), [architecture § scan list](docs/architecture.md#archive-scan-list) |
| **Preview is output-only.** Archive preview playback stays on `AVPlayer` and touches no audio input; the detail page allocates no player and pages its candidates | `ArchivePreviewOutputOnlySourceTests` (3), `ArchiveDetailPerformanceSourceTests` (2) | [architecture § preview playback](docs/architecture.md#archive-preview-playback) |
| **Tool IDs.** Each built-in tool ID is defined once (`BuiltInToolIDs.swift`); shell code orders, routes and labels tools from `ToolMetadata` (`section`, `handlesEscape`) and `ShellJobStatus` (`cancelTarget`, `cancelHelp`), never by comparing IDs | `ToolIDSourceTests` (3); `ToolSectionTests`, `InAppJobCancelRoutingTests` (AppCoreTests) | [architecture § Tool self-description](docs/architecture.md#tool-self-description) |
| **Module boundaries.** Core imports, feature→feature edges, Vault runtime edges | `ModuleBoundarySourceTests` (5); `--explicit-target-dependency-import-check error` in every build script | [ADR 020](docs/decisions/020-module-boundary-checks.md), [ADR 022](docs/decisions/022-appcore-scope-and-vault-runtime-target.md) |
| **Map current.** A change that adds a module or a module edge, moves a state owner, changes a main flow or settles an open question updates `docs/architecture-map.md` in the same commit | Judgment | [map](docs/architecture-map.md#keeping-this-map-current) |
| **Design contract.** One header, one tool-page scaffold, one rail width and material; bare `.sidebar` chrome, no full-width title strip; inspector keylines; Return and Esc only through `HubInspectorPage`; the primary action first and pinned; every `.focusable()` with `.focusEffectDisabled()`; cards only for bounded objects; `Radius.button`, no `Capsule()`; copy rules | `HubDesignContractSourceTests` (16), `HubShellChromeSourceTests`, `ToolLiquidSurfaceSourceTests`, `SettingsLiquidSourceTests`, `ArchiveLiquidSurfaceSourceTests`, `HubSetupViewSourceTests`, `MenuBarSourceTests`, `QuickAccessSourceTests`, `AppAppearanceControllerSourceTests` | [design contract](docs/design-contract.md), [ADR 018](docs/decisions/018-codex-chrome-material.md), [menu bar](docs/menu-bar-quick-access.md) |
| **Measured UI.** Verify a UI change by measurement, not by eye: dump accessibility frames of the running dev bundle (resolved by PID, window title = tool name), compare to the keyline table, then screenshot | Judgment | [design contract §7](docs/design-contract.md#7-verification-loop-do-this-every-time) |
| **Contract changes together.** If a design rule must change, change the contract doc and its guard test in the same commit | Judgment | [design contract](docs/design-contract.md) |
| **Text fits.** Text in a fixed slot or sheet fits without clipping | `HubShellChromeSourceTests.testOutputInboxStatusLinesFitBesideTheRowActions`, `HubDesignContractSourceTests.testSheetsHaveBoundedWidth`; other slots: judgment, verify in the running app | [design contract §6](docs/design-contract.md) |
| **SwiftUI state.** The `App` observes only scene-structural state; `HubShellSession` owns the selection; router requests are one-shot; settings are observed through `ToolContext.appSettings`; panes follow `hubToolIsActive`; views `@ObservedObject` session-owned models; no process-wide `NSEvent` monitors | `SwiftUIStateOwnershipSourceTests` (4) | [architecture § SwiftUI state ownership](docs/architecture.md#swiftui-state-ownership) |
| **Async tests.** An async test waits for the event it needs (job started, own store's notification), never for time or for any sender | Judgment (6de4480, 76d1867) | — |
| **Docs with behavior.** Docs that describe changed behavior change in the same commit | Judgment (76bd783, 0f27ea6); `script/check-doc-links.py` catches a broken link | [docs index](docs/README.md) |

## Working approach

Work directly from the user request, current source, Git state and validation evidence. `.planning/`, `.ai/`, `.codex/` and `.cursor/` are local-only working state on the maintainer's machine — gitignored, never part of the public tree; treat `.planning/` as historical reference only and do not require or recreate GSD workflows. Preserve unrelated work and complete the relevant checks.

## Local gates

For scoped implementation changes, run the checks relevant to the affected behavior. Run the full local gates for integration or release work. Documentation-only changes need structural and link checks (`script/check-doc-links.py`). Once sufficient checks pass, repeat them only for new changes, failures or unresolved concerns. Release requirements below still apply.

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

`./script/ci.sh` skips host-only CoreAudio recording tests that require a usable system-audio capture
device. Those tests are still part of the source suite; they are just not a reliable always-on-Mac gate.
Friendly wrappers: `./script/dev.sh run`, `./script/dev.sh doctor`, `./script/dev.sh check`.

## Release engineering

`VERSION` is the canonical release version; `BUNDLE_ID` is the permanent app identity. Release is
fail-closed and local: `script/release-all.sh`. Every public build requires a newly approved
exact-commit UAT record for the six owner-approved smoke scenarios,
produced by evidence-backed AI computer-use acceptance per
`docs/ai-acceptance-testing.md` (owner-authorized; no mandatory human approver). `approved_by`
truthfully identifies the AI agent/session and never impersonates a human; every passed check
needs durable observation/artifact evidence for the exact final SHA, and policy edits require a
new candidate before final acceptance. Never fabricate a human approval or a passed result.
See `docs/release.md` and `docs/release-validation.md`.

In-app updates use Sparkle, pinned exactly, isolated in the `AppUpdates` module. `SPARKLE_PUBLIC_ED_KEY`
holds the public signing key; the private half stays in the release owner's Keychain. The feed URL in
`nmh_update_feed_url` is permanent — installed builds poll the URL they shipped with. Builds without a
key, and debug builds without an explicit `NMH_UPDATE_FEED_URL`, ship with updates disabled rather than
unverified. See `docs/update-feed.md`.

## Ultimate De-Slop

Only when the user explicitly asks for **Ultimate De Slop**, **de-slop** or `/ultimate-de-slop`: follow
[docs/de-slop.md](docs/de-slop.md) (vendored harness in `.cursor/`, state in `.deslop/`). Ordinary reviews,
audits and scoped cleanup do not activate it.

## Git rules

- Keep commits coherent.
- Commit only green local states during execution.
- Do not push unless the prompt or user explicitly asks for push.
- Do not commit `.deslop/`, build output, `DerivedData/`, `.DS_Store`, or personal scan logs.
