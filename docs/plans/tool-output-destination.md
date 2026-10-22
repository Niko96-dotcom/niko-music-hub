# Plan: One output destination per tool run

**Status:** In progress — see [Progress](#progress)  
**Date:** 2026-10-22  
**Source:** finding 4 of the architecture review of 2026-10-22 ("One output-delivery module for tools"), now the highest-ranked finding with high confidence. A closer reading narrowed it; see [What the closer reading changed](#what-the-closer-reading-changed).  
**Scope:** `Sources/AppCore/Settings`, the four output tools (WAV Converter, Downloader, Stem Separation, Audio Recorder), the Settings output-folder picker. No change to the Output Inbox, to any user-facing sentence, or to where files land.

This plan keeps two kinds of statement apart. **Current** describes the code at `a6c3c59`. **Planned**
describes the target, which does not exist yet. When the plan is done, the lasting part moves to
[architecture.md](../architecture.md) and this file is deleted (see
[Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed).

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates green on `63630fd`; `a6c3c59` changed docs only, so no re-run |
| 1 `ToolOutputDestination` and its tests | done | `git log --grep='(output step 1)'` | strict build; `ToolOutputDestinationTests` 4/4 |
| 2 Audio Recorder | done | `git log --grep='(output step 2)'` | strict build; recorder suites 105 (3 skipped) and `ToolOutputDestinationTests`, 0 failures |
| 3 WAV Converter | done | `git log --grep='(output step 3)'` | strict build; `FeatureAudioConverterTests` 97, 0 failures |
| 4 Downloader | done | `git log --grep='(output step 4)'` | strict build; `FeatureDownloaderTests` 206 (2 skipped), 0 failures |
| 5 Stem Separation | not started | | |
| 6 Guard the rule | not started | | |
| 7 Docs, full gates, live check | not started | | |

## Revisions

1. **Step 1: no moved-root test for the destination.** `ToolOutputDestination` builds its guard with
   the default bookmark resolver, so a test cannot inject a moved bookmark. Moved roots stay covered
   where that rule lives: `VaultSettingsTests.testToolOutputGuardProtectsTheBookmarkedLocationOfAMovedRoot`.
   Adding a resolver parameter only for this test would be a seam with one adapter.
2. **Step 2: the recorder's convenience initializer takes a destination.** The plan said "renames
   only", but `AudioRecorderViewModel.init(…outputURL:outputGuard:…)` paired any folder with any
   guard. All 26 test callers and the DEBUG `RecorderOutputInboxSmoke` passed
   `ToolOutputGuard(settings: .default)`, a guard that protects nothing. Folding that into the
   initializer would hide a "protect nothing" default, which AGENTS.md forbids. So the initializer now
   takes `destination: ToolOutputDestination`, and tests say what they mean with
   `.noProtectedRoots(at:)` (a test-target helper). `RecordSystemAudioUseCase.Config` still takes a
   guard, as planned.
3. **Step 3: the converter keeps its loading overload.** The plan said the overload that loads settings
   itself was used by one test. It is used by about ten `BatchAudioConversionUseCaseTests`. It already
   loads with `try` and calls the snapshot overload, which now admits through `ToolOutputDestination`.
   So both entry points end in the same admission. Removing the overload would only churn tests. The
   completion criterion "one `convert` entry point" becomes "both entry points admit through the same
   destination".

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Output folder | The folder from Settings > Output where tools write | `AppSettings.outputFolder` |
| Admit | Check that a folder is not a music root or inside one, including a root that was moved (its bookmark) | `ToolOutputGuard.validate(_:)` |
| Destination | Where one tool run writes: the output folder and the guard that admits it, read from **one** settings snapshot | `RecordingDestination` (recorder only) |
| Handoff | Adding finished files to the Output Inbox | `addItem`, `addItems`, "handoff" in copy |

## What the closer reading changed

The review described one pipeline, "settings snapshot → guard → inbox write → failure policy", and
said each of the four tools re-implements it in its own shape. The code shows three separate
concerns of very different weight.

- **Admission is already safe and guarded.** One owner, `ToolOutputGuard`, enforced by
  `OutputGuardSourceTests`. The scatter is in *where* each tool takes its settings snapshot and pairs
  it with the guard:
  - The Downloader loads and validates in its view model.
  - The converter has two entry points.
  - Stem Separation takes its folder from view-model state but its guard from a second settings
    read at job time.
  - The recorder already does it right, with `RecordingDestination`: folder and guard from one
    snapshot.

  This part is worth a small module.
- **The handoff differences are mostly intentional.** Stem Separation writes all stems as one
  atomic unit ("a failure leaves no rows, never half a set"). Downloader adds each verified file on
  its own, so one bad file in a playlist does not hide the others. The converter adds one file per
  converted file. The recorder adds one take.

  A shared "deliver" module would hold only item construction and a `do/catch`, so it fails the
  deletion test. Making every tool treat a failed handoff the same way is a product decision. Today
  Stem Separation fails the job; the other three warn and keep the result.

  Not part of this plan.
- **"Recent outputs" is a read-side copy, not part of the pipeline.**
  - Recorder and Stem Separation each observe `.outputInboxDidChange` and filter `listItems()`.
  - The Downloader's `recentDownloads` is loaded but never shown.

  Listed as a follow-up.

So this plan deepens one thing: **a tool run writes only into a destination it loaded with `try`,
whose folder and guard come from the same settings snapshot.**

## Current architecture (observed at `a6c3c59`)

| Tool | Settings read | Guard built and checked | Folder used for the run | Paths |
| --- | --- | --- | --- | --- |
| Audio Recorder | `RecordingDestination.load(from:)` (one read, `try`) | in `RecordingDestination`, checked by `RecordSystemAudioUseCase.prepareOutputURL` | `destination.folder` | `AudioRecorderViewModel.swift:51-72`, `AudioRecorderFeature.swift:40`, `RecordSystemAudioUseCase.swift:44-60` |
| WAV Converter | view model, `Result { try loadSettings() }` | `BatchAudioConversionUseCase.convert(files:settings:…)` | `settings.outputFolder.url` | `AudioConverterViewModel.swift:176-197`, `BatchAudioConversionUseCase.swift:57-71`; a second entry point that loads settings itself (`:36-54`) is used only by a test |
| Downloader | view model, `try loadSettings()` | view model, right after | `settings.outputFolder.url` passed to the use case | `DownloaderViewModel.swift:201-225` |
| Stem Separation | view model `loadSettings()` for the folder (errors only logged), **and** a guard provider that reads settings again at job time | `StemSeparationService.validateOutputDirectory` | `request.outputRootURL`, which comes from view-model state | `StemSeparationViewModel.swift:192-200, 412-424`, `StemSeparationFeature.swift:43-45`, `StemSeparationService.swift:36-52, 172-183`, `YouTubeStemSeparationWorkflow.swift:78-104` |
| Settings output picker | already holds a snapshot | `ToolOutputGuard(settings:).validate(candidate)` | — | `SettingsView.swift:224` |
| Recovery bundle export | `try loadSettings()` | `ToolOutputGuard(settings:)` | — | `ProjectVaultRecoveryService.swift:118-128` |

Each tool keeps its own sentence for unreadable settings ("…so nothing was converted", "…so the
download didn't start", "…so separation didn't start"). That is deliberate copy and stays.

## Design A — `ToolOutputDestination`, the recorder's pattern for every tool (chosen)

Move `RecordingDestination` to AppCore under a general name, and give the other three tools the same
one-snapshot destination.

```swift
/// Where one tool run writes, and the guard that admits it, read from one
/// settings snapshot. Unreadable settings refuse the run: they never fall back
/// to defaults, which protect nothing.
public struct ToolOutputDestination: Sendable {
    /// The output folder from the snapshot.
    public let folder: URL
    /// The guard from the same snapshot. For APIs that take a guard (the recorder's use case).
    public let outputGuard: ToolOutputGuard

    /// For callers that already hold the run's snapshot (the converter).
    public init(settings: AppSettings)

    /// One throwing settings read. Passes the store's error on; each tool maps
    /// it to its own sentence.
    public static func load(from settingsStore: any SettingsStore) throws -> ToolOutputDestination

    /// Admits `folder` or a folder below it (a run's subfolder).
    public func validate(_ folder: URL) throws
}
```

Per tool:
- **Recorder.** Renames only.
- **Converter.** The use case builds `ToolOutputDestination(settings:)` from the snapshot it already
  receives. The test-only loading entry point goes.
- **Downloader.** The view model calls `load(from:)` and `validate(destination.folder)`, keeping its
  two sentences.
- **Stem Separation.** The service takes a `destinationProvider` and reads one destination at job
  start. It uses `destination.folder` as the run root and validates the run folder, or the YouTube
  download folder, with the same destination. The YouTube workflow passes that one destination to
  both of its steps. The view model keeps `outputFolderURL` only to show it.

## Design B — `ToolOutputDelivery`: admission, handoff and failure policy in one module (the review's sketch; not chosen)

One module that prepares the destination, writes the finished files to the Output Inbox, and
returns one result with one failure policy. Recent outputs could come from it too.

Why it is not chosen:
- **The handoff half is shallow.** It would hold item construction and a `do/catch`. The deletion
  test moves that code back into four tools but concentrates nothing.
- **Two of the differences are intended:**
  - atomic stems versus per-file downloads
  - per-file converter results
- **One difference is a product decision:** Stem Separation fails the job on a failed handoff,
  while the others warn.
- **The Downloader's use case is shared with Stem Separation.** If it wrote to the inbox itself,
  the YouTube intermediate audio would start to appear in the Output Inbox. Making that opt-in adds
  a flag to the shared use case.
- **The tools' run models differ widely:**
  - a live capture (recorder)
  - a pre-job title lookup (Downloader)
  - stop after the current file (converter)
  - a two-stage workflow (YouTube to stems)

  A module owning "the run" would need hooks for each.

Revisit B only if a decision makes the handoff policy the same for every tool. Even then, start with
a shared result type, not a run framework.

## Comparison

| | A: one destination per run | B: one delivery module |
| --- | --- | --- |
| Depth | Small interface (`load`, `init(settings:)`, `folder`, `validate`) over the snapshot pairing and the guard | Wide interface (options for atomicity, policy and the run model) over little shared code |
| Locality | "Folder and guard from one snapshot" lives in one type | Same for admission; handoff knowledge spreads into options |
| Caller knowledge | Load one destination, write below `folder`, validate subfolders | The same, plus delivery options and policy per tool |
| Behavior change | None for users (see requirements) | Handoff atomicity and policy change, or need flags |
| Seam | None. A value type with one implementation | None |
| Precedent | `RecordingDestination` already works in the recorder | — |

**Decision: A.** It removes the one real two-source case (Stem Separation) and gives every tool,
including the next one, the same one-line admission. It changes no user-visible behavior. No ADR is
needed. The lasting rationale (why the handoff was not unified) goes into
[architecture.md](../architecture.md) in step 7, next to the other ownership notes.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Pair the output folder with its guard from one settings snapshot | recorder only (`RecordingDestination`); the other tools each their own way | `ToolOutputDestination` (AppCore) |
| Decide whether a folder may be written (music roots, moved roots) | `ToolOutputGuard` | unchanged; `ToolOutputDestination` holds one |
| Map unreadable settings to a sentence | each tool | unchanged: each tool, its own copy |
| Stem Separation run root | view-model state, guard from a second read | the job's destination (`destination.folder`) |
| Verify finished files (WAV checks, stem scan, contained downloads) | each tool | unchanged |
| Inbox handoff and its failure policy | each tool | unchanged (see "What the closer reading changed") |

### Public interfaces

- **New:** `ToolOutputDestination` in `Sources/AppCore/Settings/ToolOutputDestination.swift`.
- **Removed:**
  - `RecordingDestination` (FeatureAudioRecorder), replaced by `ToolOutputDestination`.
  - `BatchAudioConversionUseCase.convert(files:stopController:progress:)` (the loading overload).
    Production uses the snapshot overload only.
  - `StemSeparationRequest.outputRootURL` and `YouTubeStemSeparationRequest.outputRootURL`.
- **Changed:** `StemSeparationService.init(…, outputGuardProvider:)` becomes
  `init(…, destinationProvider: @Sendable () throws -> ToolOutputDestination)`. The service gets
  `separate(request:destination:progress:)`, and `validateOutputDirectory` takes a destination.
- **Unchanged:** `ToolOutputGuard`, `OutputWriteGuard`, `OutputInboxStore`,
  `RecordSystemAudioUseCase.Config` (it still takes `outputGuard`, now `destination.outputGuard`).

### Dependency direction

```text
FeatureAudioRecorder, FeatureAudioConverter, FeatureDownloader, FeatureStemSeparation, NikoMusicHub (Settings)
        ──► AppCore.ToolOutputDestination ──► AppCore.ToolOutputGuard ──► NikoMusicCore.OutputWriteGuard
```

No new module edge. The Stem Separation → Downloader edge (ADR 020) is untouched.

## Behavior and compatibility requirements

1. **Same sentences.** Every refusal sentence stays word for word: unreadable settings per tool,
   inside an archive root, a moved root.
2. **Same locations.** Files land in the same folders. Stem Separation's run folder naming and the
   "Downloads/YouTube to Stems" folder are unchanged.
3. **Stem Separation reads settings once per run.** The run uses the saved output folder at job
   start, and the guard from the same read. The only difference: when saving a newly picked folder
   failed, the run now uses the saved folder; before, it used the folder the view showed. With
   unreadable settings, both versions refuse the run with the same sentence.
4. **Handoff unchanged.** Atomicity, item metadata, failure policy and copy stay per tool.
5. **Downloader retries unchanged.** Retries still re-read helper settings per attempt. The output
   folder is the run's destination folder, as today.
6. **Converter snapshot unchanged.** One snapshot per run admits the folder, picks the converter and
   builds every request, as today.
7. **No new `try?` settings reads.** The `OutputGuardSourceTests` baseline must not grow.
8. **Out of scope** (follow-ups below):
   - recent outputs
   - Downloader's unused `recentDownloads`
   - the handoff failure policy

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with
one commit per step.

**Verification commands used below:**
- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- Full gates: run `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from
  Terminal.app.

### Step 0: Baseline

- The full gates were green on `63630fd` (2026-10-22). `a6c3c59` only changed docs. Record that
  instead of re-running, unless more commits landed.

### Step 1: Add `ToolOutputDestination` and its tests (not wired)

- Add the type in AppCore. Its `load(from:)` is `RecordingDestination.load` unchanged.
- Add `Tests/AppCoreTests/ToolOutputDestinationTests.swift`. It covers:
  - **Settings:** an unreadable store throws, and never returns defaults; a first-run store with
    nothing saved returns the default folder.
  - **Folder:** `folder` is the snapshot's output folder.
  - **Validate:** it refuses a music root, a folder inside one, and a moved root (its bookmark), and
    admits the output folder and folders below it.
  - **One snapshot:** a destination built from settings A stays bound to A after the store changes
    to B.
- **Verify:** `B`, then `T(ToolOutputDestinationTests)`.

### Step 2: Audio Recorder

- `AudioRecorderFeature` and `AudioRecorderViewModel` use `ToolOutputDestination`.
- Delete `RecordingDestination`.
- Point `RecordingSettingsSnapshotTests` at the new type.
- **Verify:** `B`, then `T(AudioRecorderViewModelTests|RecordingSettingsSnapshotTests|RecordSystemAudioUseCaseTests|RecorderPermissionTests)`.
  The CoreAudio hardware tests stay skipped as in `ci.sh`.

### Step 3: WAV Converter

- `BatchAudioConversionUseCase.convert(files:settings:…)` admits through
  `ToolOutputDestination(settings:)`.
- Delete the loading overload.
- `BatchAudioConversionUseCaseTests.swift:242` passes the loaded settings instead. It keeps
  asserting the refusal at admission.
- **Verify:** `B`, then `T(BatchAudioConversionUseCaseTests|AudioConverterViewModelTests|AudioConverterCancelTests|AudioConverterHandoffTests)`.

### Step 4: Downloader

- `startDownload` calls `ToolOutputDestination.load(from:)` and then `validate(destination.folder)`.
- It keeps both diagnostics lines and both sentences.
- `DownloadJobOptions.outputDirectory` is `destination.folder`.
- **Verify:** `B`, then `T(DownloaderViewModelTests|DownloaderUseCaseTests|DownloaderTrustAndErrorTests)`.

### Step 5: Stem Separation

- `StemSeparationService` takes `destinationProvider`.
- `startJob` reads one destination at job start (unreadable settings →
  `StemSeparationHelperCopy.settingsUnreadable`). `separate(request:destination:progress:)` uses
  `destination.folder` as the root.
- `YouTubeStemSeparationWorkflow` reads one destination at job start, admits the download folder
  with it, and passes it to `separate`.
- Remove `outputRootURL` from both requests.
- The view model keeps `outputFolderURL` for display and the picker, and no longer builds runs from
  it.
- Replace `ToolOutputGuardTestSupport` in the stem tests with a destination helper.
- **Verify:**
  - `B`.
  - `T(StemSeparationServiceTests|StemSeparationViewModelTests|YouTubeStemSeparationWorkflowTests|StemSeparationFeatureTests)`.
  - Then the full gates, because steps 2 to 5 change every tool's admission.

### Step 6: Guard the rule

- Extend `OutputGuardSourceTests`: in Sources, `ToolOutputGuard(settings:` is built only by
  - `ToolOutputDestination.swift`
  - `SettingsView.swift`: the picker validates a candidate folder, not a run
  - `ProjectVaultRecoveryService.swift`: the bundle export
  - `RecorderOutputInboxSmoke.swift`: a DEBUG harness

  Each exception is listed with its reason, like the existing `try?` baseline.
- Add a detector self-test.
- Update the AGENTS.md rule row ("Tool output is admitted only through …") to name
  `ToolOutputDestination`.
- **Verify:** `B`, then `T(OutputGuardSourceTests)` and every `*SourceTests`. Plant a guard
  construction in a tool, see the test fail, then remove it.

### Step 7: Document, full gates, live check

- Add a "Tool output destination" section to `docs/architecture.md`. It covers the rule, the owner,
  and one line on why the handoff stays per tool (Design B).
- Update the state and rule rows in `docs/architecture-map.md`.
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check.
  - A live check with `verify-niko-music-hub`:
    1. Convert `clip-5s.wav` with the WAV Converter: the file lands in the run's output folder and
       appears in the Output Inbox.
    2. In Settings > Output, choose a folder inside the archive root: the picker refuses it with
       the same sentence as before.
    3. Run Stem Separation on the same clip (needs `--verify-tools`), or record why not.

  The Downloader live run needs network access (opt-in smoke). The Recorder must not record in a
  verification run. For both, the unit tests stand.

## Completion criteria

- `ToolOutputDestination` is the only way a tool run obtains its output folder and guard.
  `RecordingDestination` no longer exists.
- In Sources, `ToolOutputGuard(settings:` appears only in the four files listed in step 6, and the
  source test enforces it.
- Stem Separation reads settings for a run once, and both requests have no `outputRootURL`.
- Both converter entry points admit through the same `ToolOutputDestination` (revision 3).
- Every refusal sentence and every output location is unchanged. Existing tests pass; only tests
  that built the removed types or overloads were edited.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the owner. This plan is deleted.

## Follow-ups (not part of this plan)

- **Recent outputs.** One read-side model for "this tool's recent outputs" would replace the copies
  in the Recorder and Stem Separation. It would also load off the main actor, like
  `OutputInboxRefreshModel`.
- **Downloader's `recentDownloads`.** It is loaded and refreshed but never shown
  (`DownloaderViewModel.swift:499-507`). Remove it, or show it.
- **Handoff failure policy.** Stem Separation fails the job when the Output Inbox cannot take the
  stems; the other tools warn and keep the result. Unifying this needs a product decision.
