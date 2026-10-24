# Plan: One progress row and one owner for Return and Esc on the tool pages

**Status:** Approved under Niko's standing batch approval of 2026-10-24. Niko approved requirements 4 to 6 (they
change what a person sees or what a key does) on 2026-10-24. In progress — see [Progress](#progress).  
**Date:** 2026-10-24  
**Source:** finding #10 of the 2026-10-22 architecture review ("Shared job-progress and key-ownership pieces").  
**Scope:** the progress blocks and the Return and Esc keys of the tool pages (WAV Converter, Downloader, Stem
Separation, Audio Recorder, BPM Tapper), `HubInspectorPage` and a new `HubJobProgressRow` in `AppCore/Components`,
their tests, `docs/design-contract.md` and `docs/architecture.md`. No change to the Esc and ⌘. routing of finding #9,
to the jobs strip, to the archive or to what any job does.

This plan keeps two kinds of statement apart. **Current** describes the code at `a4c19c5`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and [design-contract.md](../design-contract.md), and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit. Find a step's commit with
`git log --grep='(tool page keys step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline and evidence | done | — | full gates passed on `0a31f3a`, the same tree as `a4c19c5` (finding #9's integration); live evidence below |
| 1 One progress row | done | `git log --grep='(tool page keys step 1)'` | strict build; AppCore and tool-page suites 1,376 passed, 1 failed (`ToolLiquidSurfaceSourceTests` pinned the Downloader's hand-built bar; retargeted, see revision 1), 7 skipped; Swift Testing 86 passed; a planted `ProgressView` in `StemSeparationView` failed `testToolPagesShowJobProgressThroughTheSharedRow`, then the file was restored |
| 2 The page owns its Return and Esc keys | done | `git log --grep='(tool page keys step 2)'` | strict build; AppCore and tool-page suites 1,379 passed, 1 failed (`testStopAfterThisFileHonestyCopy` pinned the hand-rolled Esc button; retargeted, see revision 2, then passed), 7 skipped; Swift Testing 86 passed; with the converter's hidden Esc button put back, `testToolPageKeysAreBoundOnlyByTheScaffold` failed, then the file was restored |
| 3 A page you left takes no key | not started | | |
| 4 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 1: two details of the shared row.** `ToolLiquidSurfaceSourceTests` required the Downloader's own
   `ProgressView(value: viewModel.progress)`; it now requires `HubJobProgressRow(` fed with
   `viewModel.showsDeterminateProgress ? viewModel.progress : nil`, the same fact. Every status line of the row wraps
   (`fixedSize(horizontal: false, vertical: true)`), as the Downloader's lines did; the converter's and Stem
   Separation's short status lines look the same. The Downloader's meter line exists while `downloadStartedAt` is set,
   which is the whole download (it is set in the same turn as `.downloading`).
2. **Step 2: one more test named the old button.** `AudioConverterViewModelTests.testStopAfterThisFileHonestyCopy`
   checked that Esc is the soft stop by finding `.keyboardShortcut(.cancelAction)` in the converter view; it now finds
   `cancelKey: HubPageKey(AudioConverterCopy.stopAfterThisFile` and `viewModel.requestStopAfterCurrent()`. The gate
   that decides which key is bound is `HubPageKey.installed(_:)`, next to the type, so a test can call it.

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Tool page | A production tool's pane, built with `HubInspectorPage` | `AudioConverterView`, `DownloaderView`, `StemSeparationView`, `AudioRecorderView`, `BPMTapperView` |
| Page key | A key a tool page answers itself: Return for its primary action, Esc for its cancel action | hidden `Button`s with `.keyboardShortcut(.defaultAction / .cancelAction)` |
| Shell Esc | Edit ▸ Cancel (Esc) and (⌘.), routed by `InAppJobCancelRouting` (finding #9) | `HubCancelCommands` |
| Visible page, page you left | The shell keeps every visited pane mounted and shows one; the others have opacity 0 and no hit testing | `AppShellView.activeToolView`, `hubToolIsActive` |
| Soft stop, hard cancel | The converter's "Stop After This File" (the file in flight finishes) and the jobs strip's or ⌘.'s cancel (the file in flight stops now) | `requestStopAfterCurrent()`, `cancelConversion()` |

## Current architecture (observed at `a4c19c5`)

### Three copies of the progress block

| Page | Lines | Shape |
| --- | --- | --- |
| WAV Converter | `AudioConverterView.swift:58-73` | bar (determinate when `overallProgress > 0`), status line; 4pt gap; bar capped at 320pt |
| Stem Separation | `StemSeparationView.swift:66-81` | bar (determinate when `progress > 0`), status line; 6pt gap |
| Downloader | `DownloaderView.swift:286-321` | bar, a meter line (`NN% complete`, `Elapsed m:ss` from `DownloaderViewModel.formatElapsed`), then the post-processing status or the slow hint; 6pt gap |

Commits 505b02a, a05db32 and 62fbe8f each made the same change in three or four of these views.

### Keys: hand-rolled on each page, and live on pages you left

- Each page installs hidden buttons for its keys: Return in the converter (`AudioConverterView.swift:360-369`), the
  Downloader (`DownloaderView.swift:337-346`) and Stem Separation (`StemSeparationView.swift:361-370`); Esc in the
  converter (soft stop, `:380-389`), Stem Separation (cancel, `:378-388`) and the Audio Recorder (stop, while capturing,
  `AudioRecorderView.swift:294-301`). The BPM Tapper's tap pad takes focus on appear and answers Space and Esc with
  `onKeyPress` (`BPMTapperView.swift:40, 128-136`); the recorder's record button answers Space when it has focus
  (`AudioRecorderView.swift:274-280`).
- The shell's Esc (finding #9) also cancels the jobs of the Downloader, Stem Separation and the converter while their
  page is visible. So Esc has two owners on the converter (soft stop and hard cancel) and on Stem Separation (both
  cancel the job). AppKit gives a window's key buttons the key before the menu, so the page wins; nothing in the code
  says so or checks it.
- The shell keeps every visited pane mounted (`AppShellView.swift:316-329`): a pane you left has opacity 0 and no hit
  testing, but its hidden key buttons and its keyboard focus stay. Only the archive follows `hubToolIsActive` for its
  app-wide effects.

### Live evidence (2026-10-24, `verify-niko-music-hub`)

1. Fresh run on `a4c19c5` and on `f62186a`: Esc on the converter during a conversion runs the soft stop (the file in
   flight finishes, the rest are "Skipped"). The page's key wins over the shell's Esc.
2. Run that visited BPM Tapper first (the tap pad took focus): Esc on the converter during a conversion did nothing,
   three times (process keys and real keyboard keys). Edit ▸ Cancel (Esc), pressed as a menu item, cancelled the
   conversion, so the shell's routing was enabled; the key never reached it or the page.

Problems:

- **No locality for progress.** "Show the elapsed time on every running job" means editing three views.
- **Two Esc owners per page, unchecked.** Which handler runs depends on AppKit's dispatch order.
- **Keys leak from pages you left.** A page's key buttons and focus stay live after the shell shows another page, so a
  key can reach a page the person cannot see, or reach nothing.

## Design A — the page declares its keys; `HubInspectorPage` installs them for the visible page only (chosen)

1. **One progress row (step 1).** In `AppCore/Components/HubJobProgressRow.swift`:

   ```swift
   /// A running job on a tool page: a bar, an optional meter line (percent and elapsed time) and an optional status
   /// line. The bar is indeterminate while `fraction` is nil.
   public struct HubJobProgressRow: View {
       public init(fraction: Double?, status: String?, startedAt: Date? = nil)
   }
   ```

   The meter line shows `NN% complete` when `fraction` is set and `Elapsed m:ss` when `startedAt` is set, as the
   Downloader does today; the elapsed format moves here from `DownloaderViewModel.formatElapsed`. The three pages call
   it; the converter keeps its 320pt cap with `.frame(maxWidth: 320)`.

2. **The page owns its keys (step 2).** `HubInspectorPage` gains two optional parameters for the action slot:

   ```swift
   /// A key a tool page answers itself (Return: primary, Esc: cancel). Installed only while it is enabled and the
   /// page is the visible one.
   public struct HubPageKey {
       public init(_ title: String, isEnabled: Bool = true, perform: @escaping @MainActor () -> Void)
   }
   HubInspectorPage(header:live:primary:list:inspector:action:primaryKey:cancelKey:)
   ```

   The rule, written in the design contract: on a tool page, Return runs the page's primary key; Esc runs the page's
   cancel key while it has an enabled one, otherwise the shell's Esc (Edit ▸ Cancel). A page declares a cancel key only
   when Esc must mean something else than the shell's cancel: the converter (soft stop; once it is requested, a second
   Esc reaches the shell and stops the file now) and the recorder (stop the take). The Downloader and Stem Separation
   declare none: the shell's Esc cancels their jobs, as for the Downloader today. No tool view installs a key button
   itself; a source test keeps `.keyboardShortcut(.defaultAction / .cancelAction)` in `HubInspectorPage` (and in
   sheets and alerts, which are not tool pages).

3. **A page you left takes no key (step 3).** `HubInspectorPage` reads `hubToolIsActive` for its key buttons (step 2).
   The BPM Tapper's tap pad and the recorder's record button ignore keys while their page is hidden; the tap pad gives
   up focus when its page is hidden and takes it again when its page is shown (today it keeps it).

## Design B — one Esc owner in the Edit menu (not chosen)

Pages publish their cancel key as a focused scene value; `HubCancelCommands`' Esc item runs the page's cancel key when
the visible page has one, otherwise the shell's routing. No page installs an Esc button. Return stays a page key.

Why it is not chosen:

- **It changes the menu.** Edit ▸ Cancel chosen with the mouse on the converter would run the soft stop, not the hard
  cancel it runs today.
- **A second path for the same fact.** The cancel key would travel as a focused value next to the job routing; panes
  that stay mounted must publish `nil` while hidden, the same gating A needs, plus the menu plumbing.
- **It fixes only Esc.** Return and Space still leak from pages you left.

B's advantage: the Esc decision is one pure function that a unit test can call, instead of AppKit's order.

## Comparison

| | A: page keys in `HubInspectorPage` | B: Esc owned by the Edit menu |
| --- | --- | --- |
| Depth | One scaffold installs every page key and gates it by visibility | One menu item decides Esc; Return stays per page |
| Locality | Keys, progress and visibility rules in two components | Esc in the commands, Return in the pages |
| Behavior | The visible page's keys as today; pages you left stop taking keys | Changes Edit ▸ Cancel's click on the converter |
| Enforcement | Source test (no key buttons outside the scaffold), unit tests of the key gating, live check | Unit test of the Esc decision |
| Risk | Low: same handlers, fewer places | Medium: a focused-value path and a menu change |

**Decision: A.** It removes the three progress copies and the six hand-rolled key buttons, gives each key one owner
on the visible page and stops keys from reaching pages the person cannot see. No ADR is needed: the rule goes into
the design contract and [architecture.md](../architecture.md) in step 4.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Show a running job's progress on a tool page | three views | `HubJobProgressRow` |
| Format the elapsed time of a running job | `DownloaderViewModel.formatElapsed` | `HubJobProgressRow` |
| Bind Return and Esc on a tool page | each view (six hidden buttons) | `HubInspectorPage` (`primaryKey`, `cancelKey`) |
| Keep keys on the visible page | nobody (archive only) | `HubInspectorPage`, the BPM tap pad, the record button (`hubToolIsActive`) |

### Interfaces

- **New:** `HubJobProgressRow`, `HubPageKey`; `HubInspectorPage(…, primaryKey:, cancelKey:)`.
- **Removed:** the hidden key buttons in the five tool views; `DownloaderViewModel.formatElapsed` and
  `elapsedCaption(at:)`.
- **Unchanged:** `InAppJobCancelRouting`, `HubCancelCommands`, `ToolMetadata.handlesEscape`, every view model's
  actions, the archive.

### Dependency direction

No new module or module edge. Both components sit in `AppCore/Components`.

## Behavior and compatibility requirements

1. **Same results on the visible page.** Return starts the same action as today (Convert, Download, Start
   Separation or Download & Separate); Esc runs the converter's soft stop, stops the recorder's take, and otherwise
   reaches the shell's Esc, as in a fresh run today.
2. **Same progress text.** Every status, percent and elapsed caption keeps its words and format.
3. **Same routing.** Finding #9's Esc and ⌘. rules and the jobs strip do not change.
4. **Pages you left take no key (behavior change; approved by Niko).** Return, Esc and Space reach only the
   visible page. Today a page you left can keep them (evidence 2: after visiting BPM Tapper, Esc on the converter did
   nothing).
5. **Stem Separation's Esc goes through the shell (approved by Niko).** Same result (the job is cancelled); the
   page's own Esc button goes, like the Downloader's.
6. **One progress layout (approved by Niko).** The converter's progress row gets the 6pt gap of the other pages
   (today 4pt); its status line wraps at 320pt instead of growing wider than the bar.
7. **Unchanged:** the soft stop and the hard cancel themselves, quit, the archive's keys, every UI text.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(tool page keys step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `PAGES`: `T(AppCoreTests)` plus `FeatureAudioConverterTests`, `FeatureDownloaderTests`, `FeatureStemSeparationTests`,
  `FeatureAudioRecorderTests`, `FeatureBPMTapperTests`
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline and evidence

- The full gates passed on `0a31f3a` (the same tree as `a4c19c5`). The live evidence above is from runs `20261024-060609-032b12`,
  `20261024-061442-e46668` (`f62186a`) and `20261024-061708-f894a2`.

### Step 1: One progress row

- Add `HubJobProgressRow`; the three pages use it; move the elapsed format and its test.
- Tests: the elapsed format (`Elapsed 0:00`, `1:05`, a start in the future clamps to 0); a source test in
  `HubDesignContractSourceTests` that tool views build no `ProgressView` for a running job outside
  `HubJobProgressRow` (the converter's per-file row bar is a list row, listed by name). Plant: a `ProgressView` in
  `StemSeparationView`, see the test fail, restore the file.
- **Verify:** `B`, then `PAGES`.

### Step 2: The page owns its Return and Esc keys

- Add `HubPageKey` and the two parameters; the five pages pass their keys and delete their hidden buttons; Stem
  Separation passes no cancel key.
- Tests: `HubInspectorPageKeysTests` for which hidden buttons the scaffold installs (none for a disabled key);
  a source test that no file under `Sources/Feature*` applies `.keyboardShortcut(.defaultAction)` or
  `.keyboardShortcut(.cancelAction)` outside sheets and alerts, and that the Downloader and Stem Separation pass no
  `cancelKey`. Plant: put the converter's hidden Esc button back; the source test fails.
- **Verify:** `B`, then `PAGES`.

### Step 3: A page you left takes no key

- `HubInspectorPage` installs key buttons only while `hubToolIsActive`; the BPM tap pad and the record button ignore
  keys while hidden; the tap pad's focus follows the page.
- Tests: the scaffold installs no key button while inactive (unit test through the gating function); source checks
  that the BPM and recorder key handlers read `hubToolIsActive`. Plant: drop the gate in `HubInspectorPage`; the test
  fails.
- **Verify:** `B`, then `PAGES`.

### Step 4: Docs, full gates, live check

- `docs/design-contract.md` §4: `HubJobProgressRow` and the key rule (action slot); `docs/architecture.md`: a short
  "Tool page keys" paragraph next to "Tool self-description"; `docs/architecture-map.md`: the state-owner row for page
  keys; `AGENTS.md`: the key rule and its enforcer.
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - A live check with `verify-niko-music-hub` (`features/wav-converter.md`, `features/bpm-tapper.md`):
    1. Visit BPM Tapper, then the converter; queue long files, Convert; Esc runs the soft stop (today: nothing).
    2. A second Esc after the soft stop stops the file in flight (the shell's Esc).
    3. On the converter, Space does not tap BPM Tapper (its tap count stays 0).
    4. Return on the converter with a queue starts the conversion; the progress row shows the bar and the status.

## Completion criteria

- One `HubJobProgressRow` for the three pages; one place formats the elapsed time.
- `HubInspectorPage` is the only tool-page place that binds Return and Esc; each key has one owner on the visible page;
  pages you left take no key.
- Requirements 1 to 3 and 7 hold; requirements 4 to 6 as Niko approved them.
- The full gates and the live check are green on the final commit.
- The design contract, `architecture.md` and `architecture-map.md` describe the result. This plan is deleted.

## Follow-ups (not part of this plan)

- **The archive's keys on a hidden pane.** The archive's own Esc, Return and arrow handlers depend on its keyboard
  focus, not on `hubToolIsActive` (only its arrow monitor and Song menu do). Check whether they leak like the tool
  pages did.
- **Elapsed time on every running job.** With one row this is one change, but it changes what the converter and Stem
  Separation show.
