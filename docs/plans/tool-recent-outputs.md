# Plan: One read-side model for a tool's recent outputs

**Status:** Approved by Niko on 2026-10-22, including requirement 7. In progress — see [Progress](#progress)  
**Date:** 2026-10-22  
**Source:** the "Recent outputs" follow-up of the tool output destination plan (removed in `b81e424`,
readable with `git show b81e424^:docs/plans/tool-output-destination.md`).  
**Scope:** a new AppCore type, the list of recent outputs on the Audio Recorder and Stem Separation pages, their
tests, one source guard and the docs. No change to the inbox handoff (how tools add rows), to the Output Inbox
panel, to `OutputInboxRefreshModel` or to `ToolOutputShelf`.

This plan keeps two kinds of statement apart. **Current** describes the code at `b81e424`. **Planned** describes
the target, which does not exist yet. When the plan is done, the lasting part moves to
[architecture.md](../architecture.md) and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit (local, not pushed; see revision 1). Find a
step's commit with `git log --grep='(recent step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline and prerequisite | done | — | `main` gained `ced1816` (Settings save error); its message reports `ci.sh` and strict E2E green, so no re-run. `ac57335` is not on `main` yet |
| 1 `ToolRecentOutputs` and its tests | done | `git log --grep='(recent step 1)'` | strict build, no warnings; `ToolRecentOutputsTests` 7 and `OutputInboxRefreshTests` 12, 0 failures; the new suite passed 10 runs in a row |
| 2 Audio Recorder | done | `git log --grep='(recent step 2)'` | strict build, no warnings; `AudioRecorderViewModelTests` and `RecordingSettingsSnapshotTests` 34, `ToolRecentOutputsTests` 7 and `SwiftUIStateOwnershipSourceTests` 4, 0 failures |
| 3 Stem Separation | done | `git log --grep='(recent step 3)'` | strict build, no warnings; `FeatureStemSeparationTests` 93 in 9 suites, `HandoffSurfacingSourceTests` 8 and `SwiftUIStateOwnershipSourceTests` 4, 0 failures |
| 4 Guard the rule | done | `git log --grep='(recent step 4)'` | branch rebased on `main` at `fd4c7d1` (has `ac57335`); strict build; every `*SourceTests` in AppCore 93, 0 failures; a planted `listItems()` in `StemSeparationViewModel` failed the new test at `:277`, then was removed |
| 5 Docs, full gates, live check | docs done (`git log --grep='(recent step 5)'`); gates and live check next | | link check of the changed docs: ok |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Commits land on the worktree branch.** This plan is carried out in the worktree branch
   `claude/zealous-ellis-cab4f4`, rebased on `main` at `ced1816`. Niko merges it into `main`.
2. **Step 1: the model follows through Combine, not an async sequence.** `NotificationCenter.publisher(for:)` with
   `.receive(on: DispatchQueue.main)` subscribes in `init`, so a change posted right after `init` is never missed,
   and the subscription ends with the model (no `deinit`). An async `notifications(named:)` loop subscribes only
   once its task starts. The Output Inbox panel uses the same publisher.

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Recent outputs | The rows of one tool in the Output Inbox, newest first, shown in the list on that tool's page | `recentRecordings` (recorder), `results` (Stem Separation) |
| Slice | The tool's rows after filter, sort and limit | — |
| Pass | One read of the inbox: `listItems()`, then filter, sort and limit | `loadRecentRecordings()`, `loadResults()` |
| Follow | Start a pass after each `.outputInboxDidChange` | the `inboxObservationTask` in each view model |
| Handoff | Adding finished files to the Output Inbox (out of scope) | `addItem`, `addItems` |

## Current architecture (observed at `b81e424`)

Two tool pages show a list of their own outputs. Each view model keeps a copy of the same read logic.

| | Audio Recorder | Stem Separation |
| --- | --- | --- |
| Published list | `recentRecordings` (`AudioRecorderViewModel.swift:81`) | `results` (`StemSeparationViewModel.swift:28`) |
| Pass | `loadRecentRecordings()` (`:502-510`) | `loadResults()` (`:267-275`) |
| Filter, sort, limit | own tool ID, `createdAt` newest first, at most 5 (`recentRecordingsLimit`, `:55`) | own tool ID, `createdAt` newest first, no limit |
| Read error | `try?`: the list becomes empty | the error text goes to `statusMessage` and the log line "Stem separation failed: …" (`diagnosticsError`, `:476-479`) |
| Follow | `onAppear()` starts a task on `.outputInboxDidChange` (`:491-500`); `deinit` cancels it (`:160`) | same (`:285-300`, `:60`) |
| Pass after own handoff | `finalizeRecording` (`:445`) | job `.completed` (`:384`) |
| View | `ToolOutputShelf(items: viewModel.recentRecordings)` (`AudioRecorderView.swift:330-339`) | `ToolOutputShelf(items: viewModel.results)` (`StemSeparationView.swift:300-308`) |

Problems:

- **The pass runs on the main actor.** `listItems()` takes the store lock, reads and decodes the whole
  `output-inbox.json` (with up to 1,000 retained missing rows plus every available row) and filters it. Tool panes
  stay mounted, so every inbox change runs one such pass on the main actor per tool page that was shown.
- **Two copies of one rule.** Filter, sort, follow, cancel and the pass after the handoff exist twice. A third copy
  (the Downloader's `recentDownloads`, never shown) is removed by `ac57335` on branch
  `claude/heuristic-shirley-d8f2e0`, not yet on `main`.
- **Every inbox change re-renders the whole tool page.** The pass assigns the list even when this tool's rows did
  not change, for example when the converter adds a file.
- **Two error behaviors without a reason.** The recorder hides read errors. Stem Separation puts an inbox read
  error into its status line and logs it as a failed separation.

The Output Inbox panel already reads off the main actor: `OutputInboxRefreshModel` (AppCore) runs
`loadRefreshedItems()` in a detached task and coalesces bursts. That model is the pattern this plan follows. It is
not reused as is, because it does a different job (see Design B and "Not chosen" below).

## Design A — `ToolRecentOutputs`, one small model per tool page (chosen)

A main-actor model in AppCore. It owns the whole read side for one tool: follow, pass off the main actor, filter,
sort, limit, coalesce, publish on change. The tool's view model creates and holds it; the tool's view observes it.

```swift
/// One tool's newest Output Inbox rows, for the list on the tool's page.
///
/// Read side only. A pass calls `listItems()` off the main actor and never
/// writes, refreshes availability or drains the corruption warning; the
/// Output Inbox panel owns those (`OutputInboxRefreshModel`).
@MainActor
public final class ToolRecentOutputs: ObservableObject {
    /// The tool's rows, newest first (`createdAt`), at most `limit`.
    /// Publishes only when the slice changes.
    @Published public private(set) var items: [OutputInboxItem] = []

    /// Follows `.outputInboxDidChange` until the model is released. Reads
    /// nothing until the first change or `refresh()`. `limit: nil` keeps every
    /// row of the tool.
    public init(store: any OutputInboxStore, toolID: ToolFeatureID, limit: Int? = nil)

    /// Starts a pass and returns at once. A request during a pass gets one
    /// follow-up pass that starts after it; a burst never causes more.
    /// A failed pass keeps the current items.
    public func refresh()

    /// Returns when no pass runs and none is pending. For tests.
    public func waitForIdle() async
}
```

Use per tool:

- **View model.** `public let recentOutputs: ToolRecentOutputs`, created in `init` from the store, the tool ID and
  the limit, replaces the published list, the limit constant, the observation task, its cancel in `deinit` and the
  pass method. `onAppear()` and the
  existing call after the own handoff call `recentOutputs.refresh()`.
- **View.** `@ObservedObject private var recentOutputs: ToolRecentOutputs`, set in `init` from
  `viewModel.recentOutputs` (the pattern `AudioRecorderView` already uses for `appSettings`). The shelf call becomes
  `ToolOutputShelf(items: recentOutputs.items, …)`. `ToolOutputShelf` stays a view over plain values, so
  `ToolOutputShelfTests` stay unchanged.

Inside, the pass and the coalescing follow `OutputInboxRefreshModel`: one task, a "needs another pass" flag, the
store call in `Task.detached(priority: .utility)`. Filter, sort and limit run in the detached task too; the main
actor only compares the slice with `items` and assigns it when it differs.

## Design B — one shared Output Inbox snapshot in `ToolContext` (not chosen)

Compose one inbox snapshot in `AppComposition`, pass it through `ToolContext`, and let the Output Inbox panel and
every tool page read from it. Sketch: `OutputInboxSnapshot` with `items`, `lastError`, `requestRefresh()` and
`recentOutputs(of:limit:)`. It follows the store and runs `loadRefreshedItems()` once per change for the whole app.

Why it is not chosen:

- **It needs Design A anyway.** A snapshot that publishes the whole inbox re-renders every page that observes it on
  every change. To publish only its own slice, each tool would need a derived, deduplicated model, which is
  `ToolRecentOutputs` on top of the snapshot.
- **It changes what the tool lists show and when the inbox writes.** The snapshot's pass refreshes availability:
  it stats every file, saves when a status changes and posts a change. Today that runs only while the Output Inbox
  panel is visible (`OutputInboxInspectorView` is mounted only then). With a shared snapshot it would run on every
  change, panel hidden or not.
- **Larger blast radius.** A new `ToolContext` member and its wiring, the panel's model moves from a view-created
  `@StateObject` to the composition, the one-time corruption warning moves with it, and the recorder's initializer
  (it takes a store, not a context) changes.
- **The gain is small.** It saves at most two off-main reads per inbox change.

Revisit B if profiling shows the inbox reads matter, or when a third reader of the inbox appears.

Also considered: give `OutputInboxRefreshModel` a scope option (whole inbox or one tool). The option would switch
the store call (`loadRefreshedItems()` or `listItems()`), the warning drain and the published error. A flag that
changes what a type does on each path is two types in one, so this is not chosen either.

## Comparison

| | A: `ToolRecentOutputs` per tool | B: one shared snapshot |
| --- | --- | --- |
| Depth | Small interface (`init`, `items`, `refresh`, `waitForIdle`) over follow, off-main pass, filter, sort, limit, coalesce, dedupe | Wide: snapshot plus per-tool projections, error and warning channels |
| Locality | "This tool's recent outputs" lives in one type; the panel's refresh stays in its own model | One owner of the displayed inbox, but tool slices still need their own owner |
| Caller knowledge | Create with store, tool ID, limit; call `refresh()` on appear and after the own handoff | The same, plus where the snapshot comes from and that it writes on refresh |
| Behavior change | Read errors (see requirement 7) | Read errors, plus availability status in tool lists and refresh writes while the panel is hidden |
| Reads per inbox change | One off-main read per shown tool page, plus the panel when visible | One |
| Seam | None. A concrete class with one implementation, tested through its interface with fake stores | None |
| Files touched | AppCore (1 new), 2 view models, 2 views, their tests | The same, plus `ToolContext`, `AppComposition`, the panel |

**Decision: A.** It removes both copies, moves the pass off the main actor, stops unrelated re-renders, and changes
no user-visible behavior except the read-error case. No ADR is needed. The lasting rationale goes into
[architecture.md](../architecture.md) in step 5.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Read, filter, sort and limit a tool's rows | each view model, on the main actor | `ToolRecentOutputs` (AppCore), off the main actor |
| Follow `.outputInboxDidChange` for a tool page | each view model | `ToolRecentOutputs` |
| Decide the tool ID and the limit | each view model | unchanged: each view model passes them to `ToolRecentOutputs` |
| Ask for a pass on appear and after the own handoff | each view model | unchanged: `recentOutputs.refresh()` |
| Show inbox read errors | Stem status line; recorder hides them | the Output Inbox panel only (requirement 7) |
| The Output Inbox panel's refresh, availability, corruption warning | `OutputInboxRefreshModel` | unchanged |
| Inbox handoff and its failure policy | each tool | unchanged ([architecture.md § Tool output destination](../architecture.md#tool-output-destination)) |

### Public interfaces

- **New:** `ToolRecentOutputs` in `Sources/AppCore/OutputInbox/ToolRecentOutputs.swift`.
- **Removed:** `AudioRecorderViewModel.recentRecordings`, `.recentRecordingsLimit`, `.loadRecentRecordings()`;
  `StemSeparationViewModel.results`, `.loadResults()`.
- **Added:** `AudioRecorderViewModel.recentOutputs`, `StemSeparationViewModel.recentOutputs`.
- **Unchanged:** `OutputInboxStore`, `JSONOutputInboxStore`, `OutputInboxRefreshModel`, `ToolOutputShelf`,
  `.outputInboxDidChange`.

### Dependency direction

```text
FeatureAudioRecorder, FeatureStemSeparation ──► AppCore.ToolRecentOutputs ──► AppCore.OutputInboxStore
```

No new module edge. The Stem Separation → Downloader edge (ADR 020) is untouched.

## Behavior and compatibility requirements

1. **Same rows.** Each list shows only its tool's rows, newest first by `createdAt`. The recorder shows at most 5,
   Stem Separation shows all. Rows keep their stored status: a pass never refreshes availability.
2. **Same triggers.** A pass runs when the page appears, after the tool's own handoff (a saved take, a completed
   stem job) and after every `.outputInboxDidChange`. Following starts when the view model is created instead of on
   the first appear. Both view models are created only in their feature's `makeView`, which `ToolPaneCache` calls
   when the tool is first shown, so this makes no visible difference.
3. **No inbox I/O on the main actor.** The store call, decode, filter, sort and limit run off the main actor.
   `refresh()` never blocks.
4. **No lost pass, no pile-up.** A request during a pass causes exactly one follow-up pass that starts after the
   request. A burst of requests never causes more than one pass in flight and one pending.
5. **Publish only on change.** An inbox change that leaves the tool's slice equal does not publish, so the tool page
   does not re-render.
6. **Read side only.** A pass never writes the inbox and never drains `takeCorruptionWarning()`, so the Output Inbox
   panel still shows the one-time corruption warning. (`listItems()` can quarantine a corrupt file, as today.)
7. **Read errors: keep the last list.** *User-visible change; needs Niko's OK.* A failed pass keeps the current
   items and shows nothing on the tool page. Today the recorder empties its list, and Stem Separation shows the
   error in its status line and logs "Stem separation failed: …" although no separation failed. The Output Inbox
   panel reads the same file and already shows and logs read errors while it is visible.
8. **Handoff unchanged.** `addItem`/`addItems` calls, atomicity, metadata, sentences and failure policy stay per
   tool.
9. **Page unchanged.** Shelf titles ("Recordings", "Results"), empty texts, subtitles and actions stay. The design
   contract is untouched.
10. **Released with its view model.** Following ends when the model is released.
11. **Fewer observers, not more.** Feature modules no longer observe `.outputInboxDidChange` or call `listItems()`.
    The one new observer is in AppCore, beside `OutputInboxRefreshModel`.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(recent step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- Full gates: run `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app (four
  recorder probe tests can fail in an agent shell at utility QoS on unchanged code).

### Step 0: Baseline and prerequisite

- The full gates were green on `da11899` (see the `b81e424` commit message). `b81e424` changed docs only. Record
  that instead of re-running, unless code commits landed since.
- Check that the Downloader removal (`ac57335`, "Drop the Downloader's unused recent downloads list") is on `main`.
  Steps 1 to 3 do not need it. Step 4 does: its guard fails while `DownloaderViewModel` still calls `listItems()`.
  If it is not on `main` by step 4, stop and ask.

### Step 1: Add `ToolRecentOutputs` and its tests (not wired)

- Add `Sources/AppCore/OutputInbox/ToolRecentOutputs.swift` with the interface above.
- Add `Tests/AppCoreTests/ToolRecentOutputsTests.swift` with its own gated store. It blocks and counts
  `listItems()`, records the calling thread, and counts `loadRefreshedItems()` and every write. (The private
  `GatedInboxStore` in `OutputInboxRefreshTests.swift` gates `loadRefreshedItems()`, so it does not fit.) The suite
  covers:
  - **Slice:** only the given tool's rows, newest first; `limit: 2` keeps the two newest; `limit: nil` keeps all.
  - **Off the main actor:** with the gated store blocked, `refresh()` returns, the main actor runs, and the store
    records that it was not called on the main thread.
  - **Coalescing:** while a pass is blocked, change the store and call `refresh()` three times. After release, the
    store saw exactly two passes and `items` shows the changed rows.
  - **Follow:** a `JSONOutputInboxStore` in a temporary folder adds a row of the tool; `items` gets it. Wait for the
    `$items` value, not for time.
  - **Publish only on change:** a row of another tool is added and a pass runs (`waitForIdle()`); `$items` emitted
    nothing new.
  - **Failure keeps the list:** the second pass throws; `items` keeps the first pass's rows.
  - **Read side only:** after several passes, the gated store counts no `loadRefreshedItems()` and no write. A
    `JSONOutputInboxStore` whose file is corrupt quarantines it on the first pass, and `takeCorruptionWarning()`
    still returns the warning afterwards.
- **Verify:** `B`, then `T(ToolRecentOutputsTests|OutputInboxRefreshTests)`.

### Step 2: Audio Recorder

- `AudioRecorderViewModel`: add `recentOutputs` (tool `Self.toolID`, limit 5). Remove `recentRecordings`,
  `recentRecordingsLimit`, `inboxObservationTask` and its cancel in `deinit`, and `loadRecentRecordings()`.
  `onAppear()` and `finalizeRecording` call `recentOutputs.refresh()`.
- `AudioRecorderView`: observe `recentOutputs` as described in Design A; the shelf reads `recentOutputs.items`.
- Tests in `AudioRecorderViewModelTests` (the recorder list has no test today):
  - `testStopRecordingFinalizesAndAddsOutputInboxItem` also checks that, after `waitForIdle()`, the take is the
    first row of `recentOutputs.items`.
  - New: a store with six recorder rows and one row of another tool shows the five newest recorder rows after
    `onAppear()` and `waitForIdle()`.
- **Verify:** `B`, then `T(AudioRecorderViewModelTests|RecordingSettingsSnapshotTests|ToolRecentOutputsTests|SwiftUIStateOwnershipSourceTests)`.
  The CoreAudio hardware tests stay skipped as in `ci.sh`.

### Step 3: Stem Separation

- `StemSeparationViewModel`: add `recentOutputs` (tool `StemSeparationService.toolID`, no limit). Remove `results`,
  `loadResults()`, `inboxObservationTask` and its cancel in `deinit`. `onAppear()` and the `.completed` branch of
  `applyObservedJob` call `recentOutputs.refresh()`. Inbox read errors no longer reach `statusMessage`
  (requirement 7).
- `StemSeparationView`: observe `recentOutputs`; the shelf reads `recentOutputs.items`.
- Tests in `StemSeparationViewModelTests`:
  - `startSeparation_enqueuesJobAndObservesProgress` and `startYouTubeSeparation_enqueuesWorkflowJob` await
    `vm.recentOutputs.waitForIdle()` before they expect four rows.
  - `loadResults_filtersByToolID` and `loadResults_sortsByCreatedAtDescending` become
    `recentOutputs_filtersByToolID` and `recentOutputs_sortsNewestFirst`: they call `vm.recentOutputs.refresh()`
    and await `waitForIdle()`. They prove the wiring (tool ID, no limit); step 1 proves the model.
- **Verify:** `B`, then
  `T(StemSeparationViewModelTests|StemSeparationServiceTests|YouTubeStemSeparationWorkflowTests|StemSeparationFeatureTests|HandoffSurfacingSourceTests|SwiftUIStateOwnershipSourceTests)`.

### Step 4: Guard the rule

- Add `testFeatureModulesReadRecentOutputsOnlyThroughToolRecentOutputs` to `HandoffSurfacingSourceTests`. Over the
  comment-stripped source of every file in `Sources/Feature*`, it fails on `listItems(` and on
  `outputInboxDidChange`. `Sources/NikoMusicHub/RecorderOutputInboxSmoke.swift` (a DEBUG harness that checks the
  handoff) is outside `Sources/Feature*` and stays allowed.
- Plant a `listItems()` call in a feature view model, see the test fail at the right file, then remove it.
- Add a row to the AGENTS.md rule table: "A tool page reads its recent outputs only through `ToolRecentOutputs`;
  feature modules never call `listItems()` or observe `.outputInboxDidChange`" | `HandoffSurfacingSourceTests`.
- **Verify:** `B`, then every `*SourceTests` in `AppCoreTests`.

### Step 5: Docs, full gates, live check

- `docs/architecture.md`: add a short section "Tool recent outputs" after § Tool output destination: the rule, the
  owner, and one line on why there is no shared snapshot (Design B).
- `docs/architecture-map.md`: add the state-owner row "A tool's recent outputs | `ToolRecentOutputs` (AppCore),
  held by the tool's view model | derived from `output-inbox.json`" and the rule row in "Intended structure".
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - A live check with `verify-niko-music-hub`, in an isolated run:
    1. Stem Separation on `clip-5s.wav` (needs `--verify-tools`): the Results shelf shows the four stems without
       leaving the page, and the Output Inbox shows them too.
    2. Relaunch with the same settings suite, open Stem Separation: Results shows those stems on appear.
    3. Before launch, seed one `audio-recorder` row into the run's isolated `output-inbox.json`, pointing at a copy
       of `clip-5s.wav`. Open the Audio Recorder: the Recordings shelf shows that row. (A verification run must not
       record.)
    4. With the Recorder page shown, convert a file with the WAV Converter, return: the Recordings shelf is
       unchanged.

## Completion criteria

- `ToolRecentOutputs` is the only code that reads a tool's recent outputs. No file in `Sources/Feature*` calls
  `listItems()` or observes `.outputInboxDidChange`, and the source test enforces it.
- Both tool pages show the same rows as before (requirement 1), loaded off the main actor.
- Requirement 7 is approved or replaced by Niko's choice, and the code matches it.
- Existing tests pass; only tests that used the removed members were edited.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md`, `docs/architecture-map.md` and AGENTS.md describe the owner and the rule. This plan is
  deleted.

## Follow-ups (not part of this plan)

- **Stem Separation list length.** The Results shelf shows every stem ever made (four rows per run). The shelf builds
  rows lazily, so this is a product question, not a speed problem: should it keep, for example, the last runs only?
- **Shared snapshot (Design B).** Revisit only on a profiling result or a third inbox reader.
