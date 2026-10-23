# Plan: One owner for helper-tool status

**Status:** Approved by Niko on 2026-10-23, including requirement 3. In progress — see [Progress](#progress).  
**Date:** 2026-10-23  
**Source:** finding #6 of the 2026-10-22 architecture review ("One helper-health module"). It also closes the
`HelperToolLocator.standard()` part of gap 5 in [architecture-map.md](../architecture-map.md).  
**Scope:** the helper probes (yt-dlp, FFmpeg, demucs-mlx), `HelperToolLocator` construction, the shell's helper
strip, the Set Up model's install signal, and how the Downloader, Stem Separation and the WAV Converter read helper
status; their tests and the docs. No change to the installer, the download/convert/separate pipelines, the Set Up
sheet's rows, the Settings Helpers pane or the design contract.

This plan keeps two kinds of statement apart. **Current** describes the code at `7646b88`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed). Find a step's
commit with `git log --grep='(helpers step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `4e94856`; `7646b88` changed docs only; no re-run |
| 1 One probe in AppCore | done | `git log --grep='(helpers step 1)'` | strict build; `AppCoreTests` 845 (2 skipped), Downloader 191 (2 skipped), Converter 89, Stem Separation 85 (Swift Testing), 0 failures; each tool suite lost exactly its moved checker tests |
| 2 One status owner and one locator | not started | | |
| 3 Tools and the strip read the owner | not started | | |
| 4 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 1: the probe's init keeps the old order.** `HelperToolProbe(runner:referenceDate:locator:)` takes its
   arguments in the checkers' order, so call sites and tests changed only the type and label names.
2. **Step 1: 27 checker cases became 14 probe tests.** Missing and broken cases run once per helper. Cases that only
   tested path resolution through a checker (saved path wins, a deleted saved path falls back) are
   `HelperToolLocatorTests` cases already; one probe test checks the fallback end to end.
3. **Step 1: `DownloaderUseCase` has one locator.** It resolves with its probe's locator; every test passed the same
   locator twice. `testAudioPostProcessingRequestCarriesConfiguredFFmpegLocationAndHelperPath` now gives the probe its fixture locator; its checker used
   the machine's `.standard()` locator before.
4. **Step 1: the Stem Separation contract doc changes.** `docs/reference/stem-separation-contract.md` drops
   `health(settings:)` and `StemBackendHealth` and points at `HelperToolProbe`. ADR 017 and the v1.4 UAT record keep
   their historical names.
5. **Step 1: two test defaults still use the machine's locator.** `AudioConverterViewModelTests.makeViewModel` and
   `DownloaderViewModelTests`' helper default to `HelperToolProbe(locator: .standard())`, as their default checkers did.
   Step 2 removes the `.standard()` defaults.
6. **Step 1: `outdated` means usable outside yt-dlp.** Only yt-dlp is ever outdated; the Converter's FFmpeg fallback and
   Stem Separation treat `.outdated` like `.ready` (the helper answered).

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Helper | An outside program a tool runs: yt-dlp, FFmpeg, ffprobe, demucs-mlx | `HelperTool` |
| Locator | Finds a helper: the saved path, then the app's Tools folder, then system folders | `HelperToolLocator` |
| Probe | Runs a helper with a version argument and reads the answer | `FFmpegHealthChecker`, `YtDlpHealthChecker`, `DemucsMLXHealthChecker` |
| Status | What a helper can do now: ready (with a version), missing, outdated, broken | `FFmpegAvailability`, `YtDlpAvailability`, `StemBackendHealth`, `HelperToolsHealthItem.State` |
| Installed | Set Up's file check: the locator finds every helper of a bundle | `HelperToolSetupModel.BundleState` |

## Current architecture (observed at `7646b88`)

### Three probes, four status types

Each feature module owns the probe for its helper, with its own result enum:

| Probe | Module | Command, timeout | Result |
| --- | --- | --- | --- |
| `FFmpegHealthChecker` | FeatureAudioConverter | `ffmpeg -version`, 15 s | `FFmpegAvailability` (missing, available, unusable) |
| `YtDlpHealthChecker` + `YtDlpVersionPolicy` | FeatureDownloader | `yt-dlp --version`, 5 s; stale-version rule | `YtDlpAvailability` (missing, available, outdated, unusable) |
| `DemucsMLXHealthChecker` | FeatureStemSeparation | `demucs-mlx --list-models`, 30 s | `StemBackendHealth` (missing, unusable, modelCacheMissing, ready) |

The shell's `HelperToolsHealthStrip` (`AppShell/HelperToolsHealthStrip.swift:109-160`) creates all three checkers
itself and maps the three enums to a fourth, `HelperToolsHealthItem.State`. Two parts are dead:
`StemBackendHealth.modelCacheMissing` is never produced, and `StemSeparationBackend.health(settings:)` has no caller
outside its own conformances.

### Nine locators, each reading the process environment

`HelperToolLocator.standard()` reads `ProcessInfo.processInfo.environment` (`NIKO_MUSIC_HUB_TOOLS_DIR`,
`NIKO_MUSIC_HUB_IGNORE_SYSTEM_HELPERS`, `HelperToolLocator.swift:64-94`). Nine default arguments call it:
`HelperToolSetupModel.swift:40`, `FFmpegHealthChecker.swift:20`, `YtDlpHealthChecker.swift:25`,
`DemucsMLXHealthChecker.swift:14`, `DemucsMLXCommandBuilder.swift:30`, `DownloaderUseCase.swift:99` and
`DownloaderHelperToolResolver.swift:8, 17, 44`. AGENTS.md allows `ProcessInfo` reads only in
`MusicHubRuntimeEnvironment`; the map lists this as gap 5.

### Each surface decides when to check

| Surface | Checks | After Set Up installs | After a helper path is saved in Settings |
| --- | --- | --- | --- |
| Stem Separation | on appear, after its own Choose, on `router.helperToolsChangeCount` | yes | no |
| Downloader | when the URL text changes (debounced), at download start | **no** | **no** |
| WAV Converter | only when a native conversion falls back to FFmpeg, at run time | — | — |
| Shell helper strip | each time its popover opens | yes | yes |
| Set Up sheet | file check when the sheet opens and at launch | yes | when the sheet opens |

`router.helperToolsChangeCount` is bumped by `AppShellView` when `helperSetup.installGeneration` changes
(`AppShellView.swift:188-190`); only Stem Separation listens (`StemSeparationViewModel.swift:279-282`).

So a Downloader that showed "yt-dlp Not Found" keeps it after Set Up installs yt-dlp, or after the person chooses
yt-dlp in Settings, until the URL is edited (`DownloaderViewModel.swift:107-178`: only `urlTextDidChange` re-checks).
Observed in source, not checked at runtime.

### The Downloader reads its error card from text

`DownloaderView.errorCard(for:)` (`DownloaderView.swift:415-431`) picks the helper card when the message contains
"yt-dlp is required", "yt-dlp path" or "outdated". So an outdated or broken yt-dlp is labeled "yt-dlp Not Found", and
"missing" has two sentences: "yt-dlp is required. Choose yt-dlp in Settings → Helpers." from the URL check, and
"yt-dlp is required. yt-dlp is not installed. Use Install Tools to add it." from a download
(`DownloaderCopy.swift:36-37`, `DownloaderUseCase.swift:47`). Stem Separation's L265 fix needed two commits
(`cdd59b2`, `9e6f0a6`) because one text field carried two meanings.

Problems:

- **No locality for helper status.** A rule such as "after an install, every tool shows the new status" must be wired
  into each view model, the strip and the shell. Only one of three tools has it.
- **Status as text.** Labels and recovery actions depend on substrings of messages.
- **A process-wide dependency in nine places,** against the project's own rule.

## Design A — one status owner in AppCore (chosen)

1. **One probe (step 1).** The three probes move to `AppCore/HelperTools/` as one value with one result type. Commands,
   timeouts, version parsing and the yt-dlp staleness rule stay as they are.

   ```swift
   public enum HelperToolStatus: Equatable, Sendable {
       case ready(version: String)
       case missing
       case outdated(current: String, minimumExpected: String)   // yt-dlp only
       case broken(message: String)
   }

   /// Runs a helper with its version argument. Stateless; safe off the main actor.
   public struct HelperToolProbe: Sendable {
       public init(locator: HelperToolLocator, runner: any ExternalProcessRunning = FoundationExternalProcessRunner())
       public func status(of tool: HelperTool, settings: HelperToolSettings) async -> HelperToolStatus
   }
   ```

2. **One owner and one locator (step 2).** `HelperToolHealth`, one instance built by `AppComposition` and carried by
   `ToolContext`, holds the last status of each helper and decides when to probe again:

   ```swift
   /// What each helper can do now, for every tool and the shell.
   @MainActor public final class HelperToolHealth: ObservableObject {
       /// nil until a surface asks for the helper; reset to nil by a change.
       @Published public private(set) var statuses: [HelperTool: HelperToolStatus]
       public let locator: HelperToolLocator
       /// Probes `tool` if its status is unknown. Surfaces call it when they appear.
       public func check(_ tool: HelperTool)
       /// Probes again now (Try Again, the strip opening) and returns the fresh status.
       public func recheck(_ tool: HelperTool) async -> HelperToolStatus
   }
   ```

   It probes again by itself after a change: it follows `appSettings` for the helper paths, and the Set Up model calls
   it when an install finishes. `router.helperToolsChangeCount` goes. The locator is built once from
   `MusicHubRuntimeEnvironment` (which gains the two Tools keys); the nine `.standard()` defaults go, and `standard()`
   no longer reads `ProcessInfo`.

3. **Tools and the strip read the owner (step 3).**
   - Downloader: shows the yt-dlp status from the owner. A URL check that failed on the helper runs again when yt-dlp
     becomes ready. The error card is chosen from a typed failure (helper status or download failure), not from text.
   - Stem Separation: reads the demucs-mlx status from the owner; its router subscription goes.
   - WAV Converter: its run-time FFmpeg fallback uses the shared probe and locator; no new display.
   - Shell strip: shows the owner's statuses and calls `recheck` for each helper when its popover opens, as it probes
     today; it creates no checker.
   - Run-time gates stay fresh: a download and the FFmpeg fallback still probe at start (`HelperToolProbe`).

## Design B — a shared change signal (not chosen)

Keep the three probes in their modules. Replace `router.helperToolsChangeCount` with a `ToolContext` signal that Set Up
installs and helper-path saves both bump; the Downloader and the Converter subscribe as Stem Separation does. Give the
Downloader a typed failure instead of substrings, and pass one locator through `ToolContext`.

Why it is not chosen:

- **Each tool still owns when to probe and how to read the answer.** A new tool, or the next surface that shows a
  helper, must remember to subscribe: the same kind of follow-up that finding #7 removed.
- **Four status types stay.** The strip keeps its own three probes and its mapping; every consumer keeps its own
  switch over a different enum.
- **Little depth.** The signal is a counter; the deletion test moves almost nothing.

B's advantage is size: no code moves between modules, and each tool's tests stay where they are.

## Comparison

| | A: one status owner | B: shared change signal |
| --- | --- | --- |
| Depth | One probe and one owner hide commands, parsing, staleness, caching and change triggers | A counter; probes and timing stay in each tool |
| Locality | Helper rules in `AppCore/HelperTools/`; one status type | Rules in three modules plus the strip; four types |
| Caller knowledge | Read `statuses[tool]`, call `check` on appear | Subscribe to the signal, run your own probe, map your own enum |
| Enforcement | No feature module builds a probe or a locator (source test); `ProcessInfo` stays out | Judgment for new subscribers |
| Risk | Medium: three tools, the strip and their tests change; probe tests move | Lower: fewer moves |

**Decision: A.** It removes the stale Downloader card, the text matching and the nine environment reads, and gives
helper status one owner. No ADR is needed: the lasting part goes into [architecture.md](../architecture.md) in step 4.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Find a helper | `HelperToolLocator.standard()` per caller | one locator from `MusicHubRuntimeEnvironment`, held by `HelperToolHealth` |
| Run a helper's version check | three checkers in three feature modules | `HelperToolProbe` (AppCore) |
| Know each helper's status, decide when to probe again | each tool, the strip | `HelperToolHealth` (AppCore, one per app) |
| Is a bundle installed (files present) | `HelperToolSetupModel` | unchanged |
| Show helper status | each tool, the strip | unchanged views, reading `HelperToolHealth` |

### Interfaces

- **New:** `HelperToolStatus`, `HelperToolProbe`, `HelperToolHealth` (AppCore); `ToolContext.helperHealth`;
  `MusicHubRuntimeEnvironment` Tools-folder values.
- **Removed:** `FFmpegHealthChecker`, `YtDlpHealthChecker`, `DemucsMLXHealthChecker`, `FFmpegAvailability`,
  `YtDlpAvailability`, `StemBackendHealth` (and `StemSeparationBackend.health(settings:)`),
  `HelperToolsHealthItem.State`'s mapping functions, `QuickAccessRouter.helperToolsChangeCount` and
  `noteHelperToolsChanged()`, the `HelperToolLocator = .standard()` default arguments.
- **Changed:** `YtDlpVersionPolicy` moves to AppCore with the probe; the Downloader's failure state becomes typed.
- **Unchanged:** `HelperToolInstaller`, `HelperToolSetupModel`'s rows and install flow, the Settings Helpers pane,
  the pipelines.

### Dependency direction

No new module or module edge. The probe and the owner join `AppCore/HelperTools/` beside the locator, installer and
Set Up model; the three feature modules and the app already import AppCore. The app target's helper strip no longer
needs the three feature modules for helper types.

## Behavior and compatibility requirements

1. **Same probes.** Same commands, arguments and timeouts; same resolution order (saved path, Tools folder, system
   folders); same yt-dlp staleness rule; the same status for the same helper.
2. **Every surface follows a change.** After Set Up installs a helper, or a helper path is saved (Settings → Helpers or
   a tool's own Choose), the Downloader, Stem Separation and the strip show the new status with no edit and no
   relaunch. A Downloader URL check that failed on yt-dlp runs again once yt-dlp is ready.
3. **Downloader labels follow the status (visible change; approved).** Missing: "yt-dlp Not Found"; outdated:
   "yt-dlp Outdated"; broken: "yt-dlp Can't Start". One sentence for missing everywhere: "yt-dlp is not installed. Use
   Install Tools, or choose it in Settings → Helpers." Today every helper failure is labeled "yt-dlp Not Found", and
   missing has two sentences. Recovery buttons stay (Install Tools, Choose Path, Try Again).
4. **No extra probes.** Nothing is probed at launch; a helper is probed when a surface first needs it and after a
   change. demucs-mlx (up to 30 s) runs only for Stem Separation or the strip, as today.
5. **Run-time gates stay fresh.** A download and the Converter's FFmpeg fallback probe at start, as today.
6. **Same environment switches.** `NIKO_MUSIC_HUB_TOOLS_DIR` and `NIKO_MUSIC_HUB_IGNORE_SYSTEM_HELPERS` keep their
   meaning (the E2E smoke and `verify-niko-music-hub --scratch-tools` / `--verify-tools` use them); they are read only
   in `MusicHubRuntimeEnvironment`.
7. **Unchanged:** Set Up's Installed / Not Installed rows and installs, the Settings Helpers pane, the Converter's
   display, the strip's look.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(helpers step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `TOOLS`: `T(FeatureDownloaderTests|FeatureStemSeparationTests|FeatureAudioConverterTests)` plus `AppCoreTests`
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline

- The full gates passed on `4e94856`; `7646b88` changed docs only. Record that instead of re-running, unless code
  commits landed since.

### Step 1: One probe in AppCore

- Add `HelperToolStatus` and `HelperToolProbe` in `Sources/AppCore/HelperTools/`; move `YtDlpVersionPolicy` there.
  Point every user of the three checkers at the probe (the Downloader's URL check and use case, the Converter's
  fallback, Stem Separation's check and command builder, the strip). Delete the three checkers, their three result
  enums, `StemSeparationBackend.health(settings:)` and the strip's mapping functions.
- Move `FFmpegHealthTests`, `YtDlpHealthCheckerTests` and `DemucsMLXHealthCheckerTests` to
  `Tests/AppCoreTests/HelperToolProbeTests.swift`, unchanged in what they assert (status per command result, staleness,
  timeouts). Update the tool tests that built a checker with a fake runner.
- **Verify:** `B`, then `TOOLS`.

### Step 2: One status owner and one locator

- `MusicHubRuntimeEnvironment` reads the two Tools keys; `HelperToolLocator.standard(...)` takes those values and no
  longer reads `ProcessInfo`. Remove the nine `.standard()` default arguments; callers pass the locator.
- Add `HelperToolHealth`; `AppComposition` builds one with the locator, `appSettings` and the probe, puts it in
  `ToolContext` and hands it to `HelperToolSetupModel`, which calls it after an install. Delete
  `router.helperToolsChangeCount`, `noteHelperToolsChanged()` and the `AppShellView` `onChange` that bumped it.
- Tests (`Tests/AppCoreTests/HelperToolHealthTests.swift`, with a fake probe, each waiting for the status publish):
  unknown until `check`; `check` probes once; a helper-path save probes again; an install probes again; `recheck`
  returns the fresh status. A source test: no `ProcessInfo` in `HelperToolLocator.swift`, and no
  `HelperToolLocator.standard(` outside `AppComposition` and the runtime.
- **Verify:** `B`, then `TOOLS` and every AppCore `*SourceTests`.

### Step 3: Tools and the strip read the owner

- Downloader: the view model reads `helperHealth.statuses[.ytDlp]`; a URL check reads it (`check` when unknown) and a
  status change to ready re-runs a failed check. Replace `errorCard(for message:)`'s substring matching with a typed
  failure; apply requirement 3's labels and sentence.
- Stem Separation: read the demucs-mlx status; delete the router subscription; its own Choose saves the path and the
  owner follows.
- Strip: read the statuses; `recheck` each helper when the popover opens; drop its feature imports if nothing else
  needs them.
- Converter: take the locator and probe from the context; no display change.
- Tests (each waits for the event it needs):
  1. Downloader: a URL check fails with yt-dlp missing; the owner then reports ready; the state becomes ready to
     download without editing the URL. Fails before this step.
  2. Downloader: missing, outdated and broken map to their own labels and the same three buttons (requirement 3).
  3. Stem Separation: a helper path saved through the settings store updates its card with no call.
  4. A source test: no feature module builds `HelperToolProbe` or a locator itself; they come from `ToolContext`.
- **Verify:** `B`, then `TOOLS`, AppCore `*SourceTests`.

### Step 4: Docs, full gates, live check

- `docs/architecture.md`: a short "Helper tools" section (locator, probe, owner, when it probes). `docs/architecture-map.md`:
  state-owner row for helper status; gap 5 without `HelperToolLocator.standard()`.
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - A live check with `verify-niko-music-hub --scratch-tools`, with `NIKO_MUSIC_HUB_IGNORE_SYSTEM_HELPERS=1` added to the
    run's launch arguments, so no helper is found and nothing is downloaded:
    1. Downloader: type a URL; the card reads "yt-dlp Not Found" with "yt-dlp is not installed. …".
    2. Settings → Helpers → Choose yt-dlp, the real Homebrew path: the Downloader turns ready to download with no
       edit (today it keeps the card). Nothing is downloaded.
    3. The sidebar helper strip shows yt-dlp ready, FFmpeg and demucs-mlx missing.
    4. Stem Separation shows its setup card; Choose demucs-mlx is not driven (no install on the Studio).

## Completion criteria

- One probe and one status owner in AppCore; no feature module or shell view builds a probe or a locator.
- `ProcessInfo` is not read in `HelperToolLocator`; the source test enforces it.
- The Downloader, Stem Separation and the strip follow installs and path saves; the Downloader's card is typed.
- Requirements 1, 2 and 4 to 7 hold; requirement 3 holds as approved. Existing tests pass, edited only where they built
  a checker or read a removed type (each recorded as a revision).
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the owner. This plan is deleted.

## Follow-ups (not part of this plan)

- **Converter after an install.** Failed rows keep the FFmpeg notice until the person retries. The Converter could read
  the owner and offer a retry when FFmpeg becomes ready; that is a UI change of its own.
- **Set Up's "Installed" and the owner's "ready".** Set Up checks files; the owner runs the helper. A bundle can be
  "Installed" while a helper is broken. One status source for both would need a design for the sheet.
