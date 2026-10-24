# Niko Music Hub — Agent Rules

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
- `AppCore`: the shared shell kit (tool registry, context, settings, jobs and quit, output inbox, diagnostics,
  shared components, helper tools) and, until it gets its own target, the Project Vault runtime.
- `FeatureArchiveBrowser`: SwiftUI feature registered through the same `ToolFeature` boundary as the
  other tools.
- Feature modules stay independent: `FeatureBPMTapper`, `FeatureAudioConverter`,
  `FeatureAudioRecorder`, `FeatureDownloader`, `FeatureStemSeparation`. The one documented exception is
  Stem Separation → Downloader; `ModuleBoundarySourceTests` and the strict import check in `./script/ci.sh`
  enforce the edges (`docs/decisions/020-module-boundary-checks.md`).
- App target is `NikoMusicHub`; bundle identity is fixed in `BUNDLE_ID`.

Start with `docs/architecture-map.md`: entry points, main flows, state owners, seams, gates, where the code
differs from these rules, and open questions. Full detail: `docs/architecture.md`. Product intent (historical
v0.1 scope): `docs/product-scope.md`.

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
  refusal, the SwiftUI state rules below, no warnings, the module edges of ADR 020, local-first and
  read-only toward music archives.

A change that adds a module or a module edge, moves a state owner, changes a main flow or settles an open
question updates `docs/architecture-map.md` in the same commit.

## Reference material

- Cubase archive/file-organization reference: `docs/reference/cubase-file-orga/`
- Stem separation contract: `docs/reference/stem-separation-contract.md`
- Architecture decisions: `docs/decisions/`
- **Current UI design contract (binding): `docs/design-contract.md`** — read it before touching any
  SwiftUI view. Superseded design history (do **not** implement from it): `docs/UI-REDESIGN-PLAN.md`

## UI design contract (do not regress)

`docs/design-contract.md` is binding and guarded by `Tests/AppCoreTests/HubDesignContractSourceTests.swift`
(plus the other `*SourceTests`). The short version:

- One header (`HubPageHeader` / `ToolHeaderBlock`), one tool-page scaffold (`HubInspectorPage`),
  one rail width + material for sidebar / inspector / inbox (`Size.chromeRailWidth`, `hubChromeMaterial`).
- Chrome material is the bare system `.sidebar` vibrancy (the Codex sidebar material, red-sheet verified —
  `docs/decisions/018-codex-chrome-material.md`): never `glassEffect`, never a veil/gradient over it.
  No full-width title strip: each column reserves the 44pt title row inside its own material.
- Inspector mirrors the sidebar: 12pt inset, labels on the "Library" keyline (y=120), 30pt controls on
  the nav-row keyline (y=144). Choices are `HubSegmentedChoice` (grid via `columns:`); fields, sliders and
  paths use `.hubInspectorRow()`. Nothing in an inspector changes height with state.
- The primary action is `HubLabeledButton(.primary, expands: true)`, FIRST in the `action` slot; it is
  pinned to the bottom on every tool (`HubPrimaryLastStack`).
- Every `.focusable()` pairs with `.focusEffectDisabled()` — the system focus ring is blue and blue is
  banned. Cards only for bounded objects. Buttons share `Radius.button` (no `Capsule()`).
- Copy: title = object, no idle status lines, empty states are one line, no "Welcome to / Manage your".
- Verify by measurement, not by eye: dump accessibility frames of the running dev bundle (resolved by
  PID, window title = tool name) and compare to the keyline table in the contract, then screenshot.
- If a rule must change, change the contract doc and the guard test in the same commit.

## SwiftUI state ownership (do not regress)

Guarded by `Tests/AppCoreTests/SwiftUIStateOwnershipSourceTests.swift`. The short version:

- The `App` observes only scene-structural state: `MenuBarExtraState` (is the extra inserted),
  `AppAppearanceController` and `HubFullScreenState` (is the key window full screen, for the ⌃⌘F
  item). It never observes `HubShellSession` — any publish there would re-evaluate
  every scene and re-init the shell (the old "LAUNCH-HANG" loops).
- `HubShellSession` is the single owner of the selected tool and panel visibility, and records
  `HubNavigationHistory` itself. The launch tool is resolved once in `AppComposition` before any scene
  exists; `AppShellView.init` has no side effects and holds no copy of the selection.
- `QuickAccessRouter` requests are one-shot values (`QuickAccessToolRequest` with a sequence,
  `openSettingsPane` consumed by `HubSettingsRoot`). Settings-pane deep links go through
  `router.requestSettingsPane` only — no `NotificationCenter` routing; feature views use
  `ToolContext.router`.
- Durable settings are observed through `ToolContext.appSettings` (`AppSettingsObserver`, fed by
  `SettingsStore.settingsChanges`) — never snapshotted in `onAppear` (cached panes never re-appear).
- Tool panes stay mounted; `@Environment(\.hubToolIsActive)` tells a pane when it is the visible one.
  App-wide effects (Song menu `focusedSceneValue`, the archive arrow-key monitor) follow that flag, never
  `onAppear`/`onDisappear`. Esc/⌘. cancel routing reads `HubShellCancelContext` as a focused scene value
  and `ShellJobStatusCenter` for jobs.
- Feature views `@ObservedObject` their session-owned view models; `@StateObject` is only for state a
  view creates itself. `@AppStorage` reads the composition's defaults suite (`defaultAppStorage`).
- Window shortcuts: ⌘W/⌘M are the system items (key-window aware); ⌃⌘F is the one custom item
  (`HubWindowCommandGroup`, key window). No process-wide `NSEvent` monitors.

## Rules and what enforces them

Each rule exists because agents broke it more than once. Prefer the enforcer over this table: if a
change trips one, fix the code, not the check. When the operator corrects a mistake, fix it and add
its rule here. A rule that is already listed with "judgment" next to it is a repeat: enforce it in the
same change (architecture, then types, then a test that names the right file or function). Drop a
row once its mistake cannot compile.

| Rule | Enforced by |
| --- | --- |
| Every count in a string goes through `CountCopy.count` / `CountCopy.noun` (NikoMusicCore) — never `"\(n) songs"` or `n == 1 ? "song" : "songs"` | `CountCopySourceTests` (all of Sources/) |
| No compiler warnings, in any configuration | `strictSwiftSettings` (`-warnings-as-errors`) on every target; `PackageSettingsSourceTests` |
| A caller that registers Undo/Redo, queues Vault work or reports success branches on `MetadataCommitOutcome`; `_ =` only for a plain edit whose refusal reports its own warning | The outcome is not `@discardableResult` and warnings fail the build; `ArchiveMetadataEditingOwnerTests` |
| Only `AppComposition.makeUserDefaults` picks the person's real defaults; tests, previews and harnesses use `InMemoryPreferenceStore` or `UserDefaults(suiteName:)` | Store initializers have no `.standard` default; `RealUserDefaultsSourceTests` |
| UI fixture launches also isolate AppKit preferences with a disposable bundle ID and an embedded settings suite; a suite alone is insufficient | `IsolatedAppLaunch` runs before SwiftUI; `IsolatedAppLaunchTests`; E2E compares the full production preferences domain |
| A tool run gets its output folder and guard from one `ToolOutputDestination.load(from:)`; other folder checks use `ToolOutputGuard(settings:)`; the archive browser's exports and New Song use `writeProtectedRoots()`; never the browse list, never `[]` | `ToolOutputGuard` is the only app-side root list (`outputProtectedRoots` is internal); no "protect nothing" defaults; `OutputGuardSourceTests` (the files that build a `ToolOutputGuard` are listed with their reasons) |
| Settings that gate a write or a Project Vault decision are loaded with `try`, and the action is refused when it throws; display-only code reads `ToolContext.appSettings` | `OutputGuardSourceTests` (per-file list of the few `try? …loadSettings()` sites that must stay, each with its reason) |
| Keep Local pins are checked, written and removed only through `VaultSettings.keepLocalPins` (`KeepLocalPins`, ADR 021); never build a key set of IDs and path spellings | `keepLocalProjectIDs` is internal to AppCore; `KeepLocalPinsSourceTests` |
| A tool page reads its recent outputs only through `ToolRecentOutputs` (AppCore); feature modules never call `listItems()` or observe `.outputInboxDidChange` | `HandoffSurfacingSourceTests.testFeatureModulesReadRecentOutputsOnlyThroughToolRecentOutputs` |
| Archive views state intent (`openSongDetail`, `showBoard`, `setBrowseLayout(list:)`, `showAnalytics`, `clearSelection`, …); only `ArchiveBrowserViewModel*.swift` writes `viewMode` and `listShowsDetail` | `ArchiveViewIntentSourceTests` |
| Each built-in tool ID is defined once (`BuiltInToolIDs.swift`); shell code orders, routes and labels tools from `ToolMetadata` (`section`, `handlesEscape`) and `ShellJobStatus` (`cancelTarget`, `cancelHelp`), never by comparing IDs | `ToolIDSourceTests`, `ToolSectionTests`, `InAppJobCancelRoutingTests` |
| Module boundaries: Core imports, feature→feature edges | `ModuleBoundarySourceTests`; `--explicit-target-dependency-import-check error` in every build script |
| UI design contract (`docs/design-contract.md`) | `HubDesignContractSourceTests` and the other `*SourceTests` |
| Text in a fixed slot or sheet fits without clipping | `HubShellChromeSourceTests.testOutputInboxStatusLinesFitBesideTheRowActions`, `HubDesignContractSourceTests.testSheetsHaveBoundedWidth`; other slots: judgment, verify in the running app |
| SwiftUI state ownership | `SwiftUIStateOwnershipSourceTests` |
| An async test waits for the event it needs (job started, own store's notification), never for time or for any sender | Judgment (6de4480, 76d1867) |
| Docs that describe changed behavior change in the same commit | Judgment (76bd783, 0f27ea6) |

## Working approach

Work directly from the user request, current source, Git state and validation evidence. `.planning/`, `.ai/`, `.codex/` and `.cursor/` are local-only working state on the maintainer's machine — gitignored, never part of the public tree; treat `.planning/` as historical reference only and do not require or recreate GSD workflows. Preserve unrelated work and complete the relevant checks.

## Local gates

For scoped implementation changes, run the checks relevant to the affected behavior. Run the full local gates for integration or release work. Documentation-only changes need structural and link checks. Once sufficient checks pass, repeat them only for new changes, failures or unresolved concerns. Release requirements below still apply.

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

Vendored locally from [Niko96-dotcom/ultimate-de-slop](https://github.com/Niko96-dotcom/ultimate-de-slop) (the `.cursor/` tree is gitignored; a fresh clone re-vendors it with the refresh command below):

- Skill: `.cursor/skills/ultimate-de-slop/`
- Slash command: `.cursor/commands/ultimate-de-slop.md`
- Runtime state (gitignored): `.deslop/`

Use the vendored workflow when the user explicitly requests **Ultimate De Slop**, **de-slop**,
`/ultimate-de-slop`, or that bounded iterative workflow. Ordinary reviews, audits and scoped
cleanup do not automatically activate the harness. Follow explicit review-only or direct-work requests.

```bash
SKILL_DIR=".cursor/skills/ultimate-de-slop"
"$SKILL_DIR/scripts/deslop-init.sh"
"$SKILL_DIR/scripts/deslop-doctor.py"
"$SKILL_DIR/scripts/deslop-status.py"
```

### Desktop / Mac (nested loop)

When `cursor-agent` (or another supported harness CLI) is on `PATH`:

```bash
export DESLOP_HARNESS=cursor   # auto-detected from the install marker
"$SKILL_DIR/scripts/deslop-loop.sh" --max-iterations 5 --priority P0,P1
"$SKILL_DIR/scripts/deslop-status.py"
# later:
"$SKILL_DIR/scripts/deslop-continue.sh"
```

Review-only: `"$SKILL_DIR/scripts/deslop-review.sh"`.

### Cloud (parent-agent mode)

Stock cloud VMs do **not** ship `cursor-agent` / `codex` / `claude`. Nested `deslop-loop.sh` agent
stages will fail doctor/`127` there. In cloud, the current agent is the parent and must play
reviewer → arbiter → fixer → verifier itself while still using the deterministic harness for state:

1. Read `.cursor/skills/ultimate-de-slop/SKILL.md` and follow its safety defaults (one finding at a
   time, no P3 fuel, no broad rewrites).
2. Run `deslop-init.sh`, then use `.deslop/index.md` / `.deslop/inventory.json` to partition work.
3. Produce high-confidence P0/P1 findings with concrete evidence; persist via the harness scripts when
   possible, otherwise keep findings in `.deslop/findings.jsonl` shape from
   `references/finding-schema.md`.
4. Fix exactly one accepted finding, run repo gates (`./script/ci.sh`; `./script/e2e_user_smoke.sh` if
   UI changed), then verify against the original finding.
5. Do not load `.deslop/runs/` into chat unless debugging. Prefer `deslop-status.py` / `deslop-next.py`.
6. Stop on the same stop policy as the skill (`no_eligible_findings`, max iterations, `.deslop/stop`,
   finalize halt).

Do **not** confuse this with the tiny Cursor plugin skill named `deslop` (branch-diff slop cleanup).
Ultimate De-Slop is the bounded whole-repo control plane.

Refresh the vendored skill from upstream when needed:

```bash
git clone --depth 1 https://github.com/Niko96-dotcom/ultimate-de-slop.git /tmp/ultimate-de-slop
/tmp/ultimate-de-slop/scripts/install/install-cursor.sh --scope local --project-dir "$(pwd)"
```

## Git rules

- Keep commits coherent.
- Commit only green local states during execution.
- Do not push unless the prompt or user explicitly asks for push.
- Do not commit `.deslop/`, build output, `DerivedData/`, `.DS_Store`, or personal scan logs.
