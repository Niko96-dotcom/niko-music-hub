# Plan: Tools describe themselves; the shell stops branching on tool IDs

**Status:** Approved under Niko's standing batch approval of 2026-10-24. In progress — see [Progress](#progress).  
**Date:** 2026-10-24  
**Source:** finding #9 of the 2026-10-22 architecture review ("Tools describe themselves; AppCore stops branching on
tool IDs").  
**Scope:** how the shell knows a tool: its ID, its place in the sidebar, what Esc and ⌘. cancel, the verb and the
Cancel help of its row in the jobs strip. Files: `AppCore/Features`, `AppCore/Jobs`, `AppCore/Shell`,
`AppCore/QuickAccess`, `AppCore/OutputInbox/OutputHandoff.swift`, the shell views and commands in `NikoMusicHub`, the
`*Feature.swift` files and the job producers in the feature modules; their tests and docs. No change to what a person
sees or to what a key does.

This plan keeps two kinds of statement apart. **Current** describes the code at `c51e10f`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit. Find a step's commit with
`git log --grep='(tool self-description step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `c51e10f` (2,900 passed, 0 failed, 8 skipped; Swift Testing 86 passed) |
| 1 One definition per tool ID | done | `git log --grep='(tool self-description step 1)'` | strict build; AppCore and feature suites 2,033 passed, 0 failed, 7 skipped; Swift Testing 86 passed; a planted `"downloader"` in `OutputHandoff.swift` failed `ToolIDSourceTests`, then the file was restored |
| 2 Sidebar sections replace `ToolCapability` | done | `git log --grep='(tool self-description step 2)'` | strict build; AppCore and feature suites 2,036 passed (3 new), 0 failed, 7 skipped; Swift Testing 86 passed; with `sidebarOrder` returning the registration order, both `ToolSectionTests` cases failed, then the file was restored |
| 3 Jobs describe their keys, verb and help | not started | | |
| 4 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 2: a stricter Settings guard.** `ToolIDSourceTests` checks that the literal `"settings"` appears in
   `Sources/` only in `SettingsFeature.swift`, not only that `ToolFeatureID("settings")` is gone. The test stubs that
   stand in for the archive or Settings take their section from one helper (`ToolSection.declared(by:)` in
   `Tests/AppCoreTests/ToolStubSupport.swift`).

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Tool ID | The stable string of a tool. It is stored (`hub.shell.*` selection, inbox items), typed (`-ui-tool`) and part of AX identifiers (`hub_tool_<id>`), so it never changes | `ToolFeatureID` |
| Pane | The tool page in the main window; Settings opens a window instead | `ToolFeature.makeView` |
| Jobs strip | The sidebar's status row of running work, with Cancel | `HubJobsStatusView` over `ShellJobStatusCenter.jobs` |
| Tool job | Running work that belongs to one tool: a download, a stem separation, a conversion | `ShellJobStatus` with a tool |
| Shell work | Running work of no tool pane: a Vault transfer, an archive scan | `ShellJobStatus` from the archive view model |
| Cancel target | The kind of work that Esc or ⌘. cancels as one group | `InAppJobCancelTarget` |

## Current architecture (observed at `c51e10f`)

### Cancel routing knows four tools by ID

`InAppJobActivity` (`AppCore/Jobs/InAppJobCancelRouting.swift:16-21`) spells four tool IDs. `jobs(for:)` (`:35-48`) finds
each target by a tool ID (download, stems) or by an extra-source key (conversion, Vault, scan). `escapeTarget`
(`:54-73`) is one `if` per tool pane; `foremost` (`:76-83`) is the ⌘. order.

| Selected pane | Esc cancels | ⌘. cancels (any pane) |
| --- | --- | --- |
| Downloader | its downloads, else nothing | the first of: downloads, stem separations, the conversion, the Vault transfer, the scan |
| Stem Separation | its separations, else nothing | (same) |
| WAV Converter | the conversion, else nothing | (same) |
| Archive Browser | nothing (the archive keeps Esc for its own views) | (same) |
| BPM Tapper, Audio Recorder, Settings, Dev Tool, none | the Vault transfer, else the scan, else nothing | (same) |

Every job of the chosen target is cancelled. A job of no target (the Dev Tool's sample job) is reached only from the
jobs strip. `HubCancelCommands` (`NikoMusicHub/Commands/HubCancelCommands.swift:32-64`) reads the target and cancels
its jobs through `ShellJobStatusCenter.cancel(id:)`.

### The jobs strip asks AppCore what a tool's row says

- `ShellJobStatus.activityVerb(for:)` (`AppCore/Jobs/ShellJobStatus.swift:64-75`) switches on three tool IDs for the
  verb of a `JobRunner` job. Its `"wav-converter"` case is dead: the converter's row is an extra source with its own
  verb.
- The converter's row is built in AppCore (`ShellJobStatusCopy.converterStatus`, `:116-138`, its fallback title and
  Cancel help at `:106-110`); `ConverterJobReporting.status` (`:88-100`) only forwards to it. The extra-source key for
  the converter is the tool ID string (`ShellJobExtraSourceID.converter = "wav-converter"`, `:79`).
- `HubJobsStatusView.help(for:)` (`NikoMusicHub/AppShell/HubJobsStatusView.swift:97-102`) compares the row's ID with the
  converter's key to pick the converter's Cancel help.
- The Vault row is built twice: inline at operation start (`FeatureArchiveBrowser/ArchiveBrowserViewModel.swift:693-713`)
  and by `ShellJobStatusCopy.vaultTransferStatus` for the restore progress poll
  (`ArchiveBrowserViewModel+ProjectVaultQueue.swift:192-210`).

### The tool order and the Settings rule are written by ID

- "Archive first, then production tools, Settings last" is written three times: `HubToolsShortcutMap.menuMetadata`
  (`AppCore/Shell/HubToolsShortcutMap.swift:15-20`), `ToolSidebarSelection.arrowKeyOrder`
  (`AppCore/Shell/ToolSidebarSelection.swift:18-21`) and `ToolSidebarView.body`
  (`NikoMusicHub/AppShell/ToolSidebarView.swift:29-46`). The Dev Tool and the design preview register after Settings
  (`AppComposition.swift:239-252`), so the grouping is needed: the registry order alone is not the sidebar order.
- "Settings opens its window and is never the main pane" is checked by ID in `ToolRegistry.contentToolID`
  (`ToolRegistry.swift:84`), `HubToolsShortcutMap` (`:12, 24-25`), `MenuBarMenuModel.dockEntries`
  (`MenuBarMenuModel.swift:49`), `HubToolsCommands.toolMenuItem` (`HubToolsCommands.swift:26`) and
  `AppShellView.selectTool` (`AppShellView.swift:8, 293`).
- The default tool is `"archive-browser"`, else `"wav-converter"`, else the first (`ToolRegistry.swift:46-50`).
- `ToolCapability` (`AppCore/Features/ToolFeature.swift:20-29`) is declared by four features and read only by three
  tests.

### A tool ID is spelled in up to eleven files

`"wav-converter"` is in 11 source files, `"archive-browser"` in 11, `"downloader"` in 7. Besides the metadata, the
spellings are: the four routing constants; feature-local constants (`StemSeparationService.toolID`,
`DownloaderViewModel.toolID`, `AudioRecorderViewModel.toolID`, `ArchiveBrowserViewModel.navigationToolID`) and
literals (`DownloaderUseCase.swift:170`, `AudioConverterViewModel.swift:746`, `BatchAudioConversionUseCase.swift:148`);
the shell (`AppShellView.swift:90, 171, 175`, `ProjectVaultSettingsView.swift:330`, `SettingsView.swift:404`, two smoke
commands); and three AppCore places that do need a named tool:

| AppCore place | Why it names a tool |
| --- | --- |
| `QuickAccessEntry.allowlist` (`QuickAccessEntry.swift:26-69`) | The menu bar menu is a curated list. Its order (Archive, Recorder, Converter, BPM, Downloader, Stems) and two icons (Converter, Stems) differ from the sidebar |
| `QuickAccessRouter` (`QuickAccessRouter.swift:71, 94`) | Search Archive… opens the archive; a converter hand-off opens the converter |
| `OutputHandoff` (`OutputHandoff.swift:4, 41, 65`) | Downloader items may be MP3, M4A, MP4 (and WebM to reveal); every other tool's item must be a WAV. Stored inbox items carry only their tool ID |

Problems:

- **No locality for a tool.** A sixth cancellable tool means editing the target enum, its filter, both routing
  functions, the verb switch and the quick-access list, all in AppCore.
- **Three copies of one order,** and five copies of the Settings rule, each by ID.
- **Unchecked agreement.** Nothing checks that the routing constants, the feature metadata and the extra-source keys
  spell the same string.

## Design A — the tool's data describes it; one catalog of tool IDs (chosen)

1. **One definition per tool ID (step 1).** `AppCore/Features/BuiltInToolIDs.swift` defines the six product tools once:

   ```swift
   /// The built-in tools' IDs, defined once. Each feature's metadata uses its own; the shell names a tool only for a
   /// curated list (the menu bar menu), a cross-tool request (Search Archive…, a converter hand-off) or a stored
   /// item's rule (`OutputHandoff`). An ID is stored and typed, so it never changes.
   public extension ToolFeatureID {
       static let archiveBrowser: ToolFeatureID = "archive-browser"
       static let bpmTapper: ToolFeatureID = "bpm-tapper"
       static let wavConverter: ToolFeatureID = "wav-converter"
       static let audioRecorder: ToolFeatureID = "audio-recorder"
       static let downloader: ToolFeatureID = "downloader"
       static let stemSeparation: ToolFeatureID = "stem-separation"
   }
   ```

   Every other spelling uses the constant; the feature-local constants go. Settings and the Dev Tool keep their one
   spelling in their feature files (app target), because after step 2 nothing else names them. The extra-source keys
   stop reusing tool ID strings (`converter` becomes `"wav-conversion"`, `audioRecorder` becomes `"recorder-take"`;
   both live only in memory).

2. **Sidebar sections replace `ToolCapability` (step 2).** The tool says where it sits:

   ```swift
   /// Where a tool sits in the sidebar. The Tools menu, the Dock menu, ⌘1…⌘9 and the arrow keys use the same order.
   public enum ToolSection: CaseIterable, Sendable, Codable, Hashable {
       /// Under "Library", first.
       case library
       /// Under "Production", in registration order. The default.
       case production
       /// The bottom row. It opens the Settings window, so it is never the main pane or the launch tool and has no
       /// ⌘ digit.
       case settings

       /// Sidebar order: each section in turn, tools in registration order.
       public static func sidebarOrder(_ metadata: [ToolMetadata]) -> [ToolMetadata]
   }
   ```

   `ToolMetadata.section` replaces `capabilities`. The three order copies call `ToolSection.sidebarOrder` (the sidebar
   view filters it per section for its captions); the five Settings checks read `section == .settings`; the default
   tool is the first Library tool, else the first tool that can be the main pane.

3. **Jobs describe their keys, verb and help (step 3).**
   - `ShellJobStatus` gains `cancelTarget: InAppJobCancelTarget?` and `cancelHelp: String?`; `sourceToolID` becomes
     "the tool whose job this is" for extra sources too (the converter sets it). A `JobRunner` job carries the verb and
     the target its tool passes to `enqueue`, so `fromJob` copies them and the verb switch goes.
   - `ToolMetadata.handlesEscape: Bool` says that the tool's pane keeps Esc: true for the Archive Browser, Downloader,
     Stem Separation and WAV Converter.
   - `InAppJobCancelTarget` stays the one ordered list of cancel targets (its case order is the ⌘. order; it becomes
     `Comparable`). `InAppJobActivity` and its filters go. Routing is two functions over the job list:

     ```swift
     public enum InAppJobCancelRouting {
         /// Esc. A pane that handles Esc cancels its own tool's jobs that have a target (the archive owns none, so Esc
         /// stays with its views). Any other pane cancels the shell work (no tool) of the first target present.
         public static func escapeJobs(selectedTool: ToolMetadata?, in jobs: [ShellJobStatus]) -> [ShellJobStatus]
         /// ⌘.: every job of the first target present, whatever pane is selected.
         public static func commandPeriodJobs(in jobs: [ShellJobStatus]) -> [ShellJobStatus]
     }
     ```

   - `HubShellCancelContext` carries the selected tool's metadata instead of its ID.
   - The converter builds its own row in `FeatureAudioConverter` (title, fallback, verb, Cancel help, target);
     `ConverterJobReporting` and the converter copy leave AppCore. The jobs strip shows `job.cancelHelp`. Both Vault
     publishes use `ShellJobStatusCopy.vaultTransferStatus`.

What still names a tool in AppCore after step 3: the catalog itself, the curated menu bar list, the router's two
cross-tool requests and `OutputHandoff`'s Downloader rule (see [Follow-ups](#follow-ups-not-part-of-this-plan)). None
of them is a routing or ordering branch.

## Design B — feature-owned IDs, behavior behind `ToolFeature` (not chosen)

Each feature module defines its own ID; AppCore names no tool at all. Key handling becomes protocol behavior
(`ToolFeature.escapeCancels(_ jobs:) -> [ShellJobStatus]?`, `nil` for "Esc goes to shell work"), each job carries a
numeric ⌘. rank chosen by its tool, and the curated menu bar list and the Downloader handoff rule move to the
composition root.

Why it is not chosen:

- **The menu bar list's tests would lose their target.** `QuickAccessCommandTests`, `HandoffSurfacingSourceTests` and
  `MenuBarMenuModelTests` check the real list; no test target sees the app target, so they would turn into source-text
  checks: a weaker gate.
- **The ⌘. order would be spread over four modules** as numbers that only make sense together. In A it is one
  enum's case order.
- **The Downloader rule depends on stored items.** Moving it needs a stored marker on inbox items (with a migration),
  which is its own change.
- **A protocol method for Esc** is behavior that a fake must reimplement; in A the rule is data plus one tested
  function.

B's advantage: AppCore knows no tool at all, and a new tool touches only its module and the composition root.

## Comparison

| | A: data + one ID catalog | B: feature-owned IDs + protocol behavior |
| --- | --- | --- |
| Depth | Routing and ordering are two small functions over data the tools supply | The same rules, split over protocol methods per tool |
| Locality | One file per question: IDs in the catalog, ⌘. order in `InAppJobCancelTarget`, a tool's row and keys in its module | A tool's facts in its module; the ⌘. order spread over four modules |
| New cancellable tool | Its module, plus one case in `InAppJobCancelTarget` and one catalog line | Its module and the composition root |
| Tests | Existing value tests keep their targets; routing tests stay pure | Menu bar tests become source checks |
| Risk | Low: same strings, same order, same key results | Medium: moves tested data out of test reach |

**Decision: A.** It removes every routing and ordering branch on a tool ID, defines each ID once and keeps every value
test. No ADR is needed: the lasting part goes into [architecture.md](../architecture.md) in step 4.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Define a tool's ID | up to 11 files per ID | `BuiltInToolIDs.swift` (product tools); `SettingsFeature`, `DevToolFeature` |
| Say where a tool sits in the sidebar | three ID filters | `ToolMetadata.section`; `ToolSection.sidebarOrder` |
| Say that a pane is Settings | five ID checks | `ToolSection.settings` |
| Say whether a pane keeps Esc | `escapeTarget`'s `if` chain | `ToolMetadata.handlesEscape` |
| Say what a job is for the keys | `InAppJobActivity.jobs(for:)` filters | `ShellJobStatus.cancelTarget`, `sourceToolID` (set by the job's tool) |
| Order of ⌘. | `foremost`'s `if` chain | `InAppJobCancelTarget` case order |
| A row's verb and Cancel help | `activityVerb(for:)`, `HubJobsStatusView.help(for:)` | the job's tool, through `ShellJobStatus` and `Job` |

### Interfaces

- **New:** `ToolFeatureID.archiveBrowser` … `.stemSeparation`; `ToolSection`; `ToolMetadata.section`,
  `ToolMetadata.handlesEscape`; `ShellJobStatus.cancelTarget`, `ShellJobStatus.cancelHelp`; `Job.activityVerb`,
  `Job.cancelTarget`; `InAppJobCancelRouting.escapeJobs`, `commandPeriodJobs`.
- **Changed:** `JobRunning.enqueue` takes the verb and the target; `HubShellCancelContext` holds the selected tool's
  metadata.
- **Removed:** `ToolCapability`, `ToolMetadata.capabilities`, `InAppJobActivity`, `InAppJobCancelRouting.escapeTarget`
  and `foremost`, `ShellJobStatus.activityVerb(for:)`, `ConverterJobReporting`, the converter copy in
  `ShellJobStatusCopy`, `HubToolsShortcutMap.archiveToolID` and `settingsToolID`, the feature-local tool ID constants.
- **Unchanged:** every ID string, `ShellJobStatusCenter`'s interface, quit (ADR 019), the jobs strip's layout, the
  menu bar list, `OutputHandoff`'s rules.

### Dependency direction

No new module or module edge. The catalog and `ToolSection` sit in AppCore, which every feature imports.

## Behavior and compatibility requirements

1. **Same IDs.** Every tool ID string stays, so stored selections, `-ui-tool`, stored inbox items and AX identifiers
   (`hub_tool_<id>`) keep working. The two renamed extra-source keys are in memory only.
2. **Same order everywhere.** Sidebar (captions, rows, Settings at the bottom), Tools menu (and its divider before
   Settings), ⌘1…⌘9, arrow keys and the Dock menu show the same tools in the same order as today, also with the Dev
   Tool shown. The menu bar menu does not change (order, labels, icons).
3. **Same keys.** Esc and ⌘. cancel the same jobs as in the table above, for every pane and every mix of running work.
   The existing routing tests keep their cases.
4. **Same jobs strip.** Every row keeps its text (`Downloading “x” · 42%`, `Separating …`, `Converting …`,
   `Transferring …`, `Scanning archive`, the Dev Tool's `Running …`) and its Cancel help.
5. **Same launch tool** for every registry the app builds. Only a registry without a Library tool would now default
   to its first pane tool instead of the WAV Converter; the app always registers the archive first, and a failed
   registry is empty.
6. **Unchanged:** quit and its alert (ADR 019), what the jobs strip's Cancel does, the inbox, every UI text.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(tool self-description step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `SHELL`: `T(AppCoreTests)` plus the test targets of the features the step touched
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline

- The full gates passed on `c51e10f`. No code commits landed since.

### Step 1: One definition per tool ID

- Add `Sources/AppCore/Features/BuiltInToolIDs.swift` as in Design A.
- Every feature's metadata and every other spelling use the constant; remove `StemSeparationService.toolID`,
  `DownloaderViewModel.toolID`, `AudioRecorderViewModel.toolID` and `ArchiveBrowserViewModel.navigationToolID` (their
  callers and tests use the constant). Rename the two extra-source keys.
- `HandoffSurfacingSourceTests`' ROUT-06 check (the stem tool's ID is `stem-separation`, no stem-downloader ID) reads
  the catalog instead of `StemSeparationService.swift`.
- New source test `ToolIDSourceTests`: the six ID literals appear in `Sources/` only in `BuiltInToolIDs.swift`. Plant
  a `"downloader"` literal in `OutputHandoff.swift`, see the test fail, restore the file from a backup copy.
- **Verify:** `B`, then `SHELL` for every target (the step touches all features).

### Step 2: Sidebar sections replace `ToolCapability`

- Add `ToolSection` and `ToolMetadata.section` (default `.production`); delete `ToolCapability` and `capabilities`.
  The Archive Browser declares `.library`, Settings `.settings`.
- `HubToolsShortcutMap.menuMetadata`, `commandDigit`, `ToolSidebarSelection.arrowKeyOrder`, `ToolSidebarView`,
  `MenuBarMenuModel.dockEntries`, `HubToolsCommands`, `ToolRegistry` (`contentToolID`, `preferredDefaultFeatureID`)
  and `AppShellView.selectTool` use the section. `HubToolsShortcutMap` loses its two ID constants.
- Tests: the test fixtures that register an archive or Settings stub declare its section; the capability assertions
  in `FeatureRegistryTests`, `AudioConverterFeatureTests` and `StemSeparationFeatureTests` become section assertions;
  a new `ToolSection.sidebarOrder` test with the production registration order (Archive, BPM, Converter, Recorder,
  Downloader, Stems, Settings, Dev Tool, design preview) expects Settings last. The source checks that name
  `settingsToolID` (`HubSettingsPaneIDTests`, `HubToolsShortcutMapTests`) check the section instead. `ToolIDSourceTests`
  also checks that `ToolFeatureID("settings")` appears nowhere in `Sources/`. Plant: let `sidebarOrder` keep the
  registration order; the new test fails.
- **Verify:** `B`, then `SHELL` for every target.

### Step 3: Jobs describe their keys, verb and help

- `InAppJobCancelTarget: Comparable`; `ShellJobStatus.cancelTarget`, `cancelHelp`; `Job.activityVerb`,
  `Job.cancelTarget`; `JobRunning.enqueue(title:sourceToolID:activityVerb:cancelTarget:operation:)` (the test doubles
  follow). `ShellJobStatus.fromJob` copies the job's verb and target; delete `activityVerb(for:)`.
- `ToolMetadata.handlesEscape`; the four features set it. `InAppJobCancelRouting.escapeJobs` and `commandPeriodJobs`
  replace `InAppJobActivity`, `escapeTarget` and `foremost`; `HubShellCancelContext(selectedTool:)`; `HubCancelCommands`
  cancels the returned jobs.
- Producers: Downloader (`.downloader`, `"Downloading"`, `.download`), Stem Separation (both enqueues:
  `"Separating"`, `.stemSeparation`), the converter row (moved into `FeatureAudioConverter`: `sourceToolID:
  .wavConverter`, `"Converting"`, `.conversion`, its Cancel help), the Vault row (both publishes through
  `vaultTransferStatus`, `.vaultTransfer`), the scan row (`.scan`), the Dev Tool's sample job (`"Running"`, no
  target).
- `HubJobsStatusView` shows `job.cancelHelp ?? ShellJobStatusCopy.cancel`.
- Tests: `InAppJobCancelRoutingTests` keeps every case through the new functions, with job fixtures built as their
  tools build them; new cases for the archive pane (Esc cancels nothing while a Vault transfer and a scan run), a pane
  that does not handle Esc (the Vault transfer before the scan), an idle Downloader pane (nothing), and a job without a
  target (never). The converter's row tests move to `FeatureAudioConverterTests` and check the target and the help.
  `StemSeparationViewModelTests` routes through `StemSeparationFeature().metadata`. A Downloader test checks that its
  runner job carries `.download` and the verb. Plants: drop `handlesEscape` from the Downloader feature (the idle
  Downloader pane case fails); drop the converter row's target (its routing test fails).
- **Verify:** `B`, then `SHELL` for every target.

### Step 4: Docs, full gates, live check

- `docs/architecture.md`: a short "Tool self-description" paragraph in the shell part (the catalog, the sections, the
  key rule and where the ⌘. order lives). `docs/architecture-map.md`: the state-owner and intended-structure rows for
  the tool order and the key routing; the `ToolFeature` seam row. `AGENTS.md` table: the tool ID rule and its
  enforcer.
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - A live check with `verify-niko-music-hub` (archive profile, `features/app-shell-navigation.md`,
    `features/menus-and-windows.md`, `features/wav-converter.md`):
    1. The sidebar shows Library (Archive Browser), Production (BPM Tapper, WAV Converter, Audio Recorder, Downloader,
       Stem Separation) and Settings at the bottom; the Tools menu has the same order, ⌘1…⌘6, a divider and Settings;
       ⌘3 opens the WAV Converter; arrow keys in the sidebar skip Settings; the menu bar menu keeps its list.
    2. On the WAV Converter, start a conversion of the run's input files: the jobs strip shows `Converting “…”` with its
       Cancel help; Esc stops the conversion.
    3. Start a conversion again, select BPM Tapper, press ⌘.: the conversion stops. Start it again, select BPM Tapper,
       press Esc: the conversion keeps running (Esc on a pane that does not handle Esc cancels only shell work).
    4. On the Archive Browser with no job, Esc keeps its archive meaning (closes the song detail).

## Completion criteria

- Each built-in tool ID is defined once; `ToolIDSourceTests` enforces it.
- No routing or ordering code branches on a tool ID; the sidebar order and the Settings rule come from
  `ToolMetadata.section`; `ToolCapability` is gone.
- Esc and ⌘. read only `ShellJobStatus.cancelTarget`, `sourceToolID` and `ToolMetadata.handlesEscape`; the ⌘. order is
  `InAppJobCancelTarget`'s case order.
- Every jobs-strip row gets its verb and Cancel help from its tool.
- Requirements 1 to 6 hold; existing tests pass unchanged except where a step names the change.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the result. This plan is deleted.

## Follow-ups (not part of this plan)

- **One menu order (needs Niko's decision).** The menu bar menu lists the tools in another order than the sidebar and
  uses other icons for the WAV Converter and Stem Separation. Building it from the registry would make every menu
  agree, but it changes what a person sees.
- **⌘. order (needs Niko's decision).** ⌘. prefers downloads, then stem separations, then the conversion, an order that
  grew one case at a time. A rule such as "the selected pane's own work first" may be what a person expects.
- **The Downloader's handoff rule.** `OutputHandoff` decides by tool ID which file types an inbox item may hand off.
  The producing tool could store that rule on the item; old items need a fallback, so it is its own change.
- **Finding #10.** One progress row for the tool pages and one owner for Esc inside a tool pane.
