# Plan: One recording signal, built by the composition and passed through the tool context

**Status:** Assigned by the coordinating session as the follow-up of finding #11; runs under Niko's standing batch
approval of 2026-10-24 (no stop trigger applies: nothing a person sees changes, no Vault or archive data, no product
decision, no test or gate weakened). In progress — see [Progress](#progress).  
**Date:** 2026-10-24  
**Source:** the follow-up "`AudioCaptureActivity.shared`" of the preview injection plan (finding #11 of the 2026-10-22
architecture review). It removes the first half of gap 5 in [architecture-map.md](../architecture-map.md).  
**Scope:** how the recording signal (`AudioCaptureActivity`) is created and reached by the Audio Recorder and the
archive's preview playback: `AppCore` (`AudioCaptureActivity`, `ToolContext`), `AppComposition`, `FeatureAudioRecorder`,
`FeatureArchiveBrowser`, their tests and docs. No change to what the person sees or hears: recording still pauses
preview playback, blocks Play and Compare until the take ends, and never resumes audio by itself.

This plan keeps two kinds of statement apart. **Current** describes the code at `f62186a`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit. Find a step's commit with
`git log --grep='(capture injection step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `9733644` (finding #11, step 4): 2,901 passed, 0 failed, 8 skipped; Swift Testing 86 passed; strict E2E exit 0; no re-run |
| 1 The tool context carries one recording signal | done | `git log --grep='(capture injection step 1)'` | strict build; capture suites 60, 0 failures (1 new); with a static fallback in `ToolContext` the new test failed 2 assertions |
| 2 The recorder and the archive use the context's signal | done | `git log --grep='(capture injection step 2)'` | strict build; `FeatureArchiveBrowserTests`, `AppCoreTests`, recorder view-model suites: 1,561 passed, 0 failed, 2 skipped; plants (a) and (b) each failed the new test with 2 assertions, plant (c) failed the source guard; no `AudioCaptureActivity.shared` left |
| 3 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

(none yet)

## Terms

| Term | Meaning | Name in code |
| --- | --- | --- |
| Recording signal | Whether a take is capturing system audio, from start until its file is finalized | `AudioCaptureActivity.isActive` |
| Owner | One recorder's claim on the signal; the signal is active while any owner holds it | `setActive(_:owner:)` |
| Preview session | The archive's playback owner; it pauses on the signal and blocks Play and Compare while it is active | `ArchivePreviewSession` |

## Current architecture (observed at `f62186a`)

`AudioCaptureActivity.shared` (`Sources/AppCore/AudioCaptureActivity.swift:8`) is the only instance. AppCore owns it so
that the two features never import each other.

| File | Lines | Use |
| --- | --- | --- |
| `AudioRecorderViewModel.swift` | 55-63 | the `recordingState` `didSet` calls `.shared.setActive(_:owner:)` for `.starting`, `.recording`, `.reconnecting`, `.stopping` |
| `AudioRecorderViewModel.swift` | 158-162 | `deinit` releases the owner on `.shared` |
| `ArchivePreviewSession.swift` | 32, 44-48 | `init(player:capture: = .shared)` observes `capture.$isActive`: active pauses the player, inactive re-arms the selection |
| `ArchiveBrowserViewModel.swift` | 31 | `let previewSession = ArchivePreviewSession()`, so the default `.shared` |
| `ArchivePreviewOutputOnlySourceTests.swift` | 36 | forbids `AudioCaptureActivity.shared.setActive` in the archive's sources: the preview only observes the signal |

Both features already receive the one `ToolContext` that `AppComposition.make()` builds: the archive view model in its
initializer, the recorder in `AudioRecorderFeature.makeView(context:)`, which builds its view model once
(`AudioRecorderFeature.swift:27-47`). The preview tests already build their own `AudioCaptureActivity()`.

Problems:

- **Hidden dependency.** Nothing in an initializer says that the recorder and the archive depend on the signal, or that
  they must share it (AGENTS.md bans `.shared` singletons).
- **No isolation.** Every recorder view model and every archive view model a test builds shares one process-wide
  signal.
- **No check of the link.** No test shows that a recording in the recorder pauses the archive. The preview tests set
  the signal by hand; the recorder tests never look at it.

## Design A — one signal on `ToolContext` (chosen)

1. `ToolContext` gets `audioCaptureActivity: AudioCaptureActivity`. `AppComposition.make()` builds one and passes it,
   like the job center, router and helper health. A context built without one (tests, the archive smoke) gets its own,
   like the context's other shell-wide objects (map gap 2).
2. The archive view model builds its preview session from `context.audioCaptureActivity`. `ArchivePreviewSession`
   loses its default, so a session without a signal does not compile.
3. The recorder view model takes `audioCaptureActivity: AudioCaptureActivity?` (nil: nobody listens, like
   `jobStatusCenter`). `AudioRecorderFeature` passes `context.audioCaptureActivity`. The feature's view-model wiring
   moves into `makeViewModel(context:capturePort:)`, so a test can run the feature's own wiring with a fake capture
   port instead of CoreAudio.
4. `AudioCaptureActivity.shared` is deleted.

## Design B — initializer parameters wired in `AppComposition` (not chosen)

`AudioRecorderFeature(audioCaptureActivity:)` and a new `audioCaptureActivity:` parameter on the archive view model's
initializers, both filled in `AppComposition.make()`.

Why it is not chosen:

- **Two wiring paths for one object.** The composition passes the same instance twice, and the recorder feature stores
  it only to forward it to the view model it builds later. `ToolContext` is already the shared tool wiring, and both
  features already receive it.
- **More public surface.** The archive view model has three initializers (two public); each would take the parameter.

B's advantage: the dependency shows on the feature's initializer and `ToolContext.init` gets no new default. A, with
the end-to-end test below, makes the shared instance just as explicit at the one place that builds it.

**Decision: A.** No ADR: the lasting part goes into [architecture.md](../architecture.md) and
[architecture-map.md](../architecture-map.md) in step 3.

## Planned architecture

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| The recording signal | `AudioCaptureActivity.shared` | one `AudioCaptureActivity` from `AppComposition.make()`, in `ToolContext.audioCaptureActivity` |
| Set the signal | the recorder view model, on `.shared` | the recorder view model, on the instance it is given |
| Pause on the signal | the preview session, on `.shared` by default | the preview session, on the instance the archive view model gives it |

- **New:** `ToolContext.audioCaptureActivity`; `AudioRecorderViewModel.init(…, audioCaptureActivity:)`;
  `AudioRecorderFeature.makeViewModel(context:capturePort:)` (internal); `AudioCaptureActivity`'s init is nonisolated so
  `ToolContext` can build its default (as `QuickAccessRouter` does).
- **Removed:** `AudioCaptureActivity.shared`; the default of `ArchivePreviewSession.init(capture:)`.
- **Unchanged:** `setActive(_:owner:)`, `isActive`, the session's pause rules, every UI string.
- **Dependency direction:** no new module edge in `Sources/`. `AppCoreTests` gets `FeatureAudioRecorder` as a test
  dependency (it already has `FeatureArchiveBrowser`), for the end-to-end test.

## Behavior and compatibility requirements

1. **The person sees and hears the same.** [design-contract.md § Archive selection and persistent preview
   player](../design-contract.md#archive-selection-and-persistent-preview-player): recording pauses preview playback,
   blocks Play and Compare, defers the transport replacement until capture ends, and never resumes audio by itself.
   The existing preview and recorder tests pass unchanged except where a step names the change.
2. **One signal in the app.** Production builds one `ToolContext`, so the recorder and the archive share one signal for
   the app's lifetime, as today.
3. **No singleton at the end.** No `AudioCaptureActivity.shared` in `Sources/` or `Tests/`.
4. **The archive only observes.** The source guard keeps any `setActive(` call out of the archive's sources; it is at
   least as strict as the `.shared.setActive` entry it replaces.
5. **The link is tested.** One test runs the recorder's own wiring and the archive view model on one context: starting
   a take pauses the playing preview, stopping it leaves the preview paused and lets Play work again.
6. **Lane A safety.** `ToolContext` and `AppComposition` change by one field each; lane A (findings #9/#10) also edits
   AppCore shell files. Rebase on origin/main before the full gates.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(capture injection step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `CAPTURE`: `T(ToolContextTests|AudioCaptureActivityWiringTests|ArchivePreviewSessionTests|ArchivePreviewRouteObserverTests|SongCardInteractionTests|ArchivePreviewOutputOnlySourceTests|AudioRecorderViewModelTests|ModuleBoundarySourceTests|PackageSettingsSourceTests)`
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app, one UI lane
  at a time

### Step 0: Baseline

- The full gates passed on `9733644`, the last code state of finding #11 (`f62186a` changed only docs). Record that
  instead of re-running.

### Step 1: The tool context carries one recording signal

- `AudioCaptureActivity`: `nonisolated public init()`. `.shared` stays for this step; both features still use it.
- `ToolContext`: `public let audioCaptureActivity`, init parameter `audioCaptureActivity: AudioCaptureActivity? = nil`,
  default a new instance.
- `AppComposition.make()`: `let audioCaptureActivity = AudioCaptureActivity()`, passed to the one `ToolContext`.
- Test (`ToolContextTests`): two contexts built without a signal never share one. Plant: a static fallback instance in
  `ToolContext` fails it.
- **Verify:** `B`, then `CAPTURE`.

### Step 2: The recorder and the archive use the context's signal

- `AudioRecorderViewModel`: both initializers take `audioCaptureActivity: AudioCaptureActivity? = nil`; the `didSet`
  and `deinit` use it.
- `AudioRecorderFeature`: `makeViewModel(context:capturePort:)` builds the view model with
  `context.audioCaptureActivity`; `viewModel(for:)` calls it with `CoreAudioTapAdapter()`.
- `ArchiveBrowserViewModel`: `previewSession = ArchivePreviewSession(capture: context.audioCaptureActivity)` in the
  initializer. `ArchivePreviewSession.init(capture:)` has no default.
- Delete `AudioCaptureActivity.shared`.
- `ArchivePreviewOutputOnlySourceTests`: `AudioCaptureActivity.shared.setActive` becomes `setActive(` (any receiver).
  Plant: `capture.setActive(false, owner: UUID())` in the session's initializer fails it.
- `Package.swift`: `AppCoreTests` depends on `FeatureAudioRecorder`.
- New test `AudioCaptureActivityWiringTests` (AppCoreTests): one context; the archive view model auditions a fixture
  WAV; the recorder from `AudioRecorderFeature.makeViewModel(context:capturePort:)` with a fake port starts a take.
  The session reports capture and stops playing; Play does nothing. Stopping the take clears capture, the preview stays
  paused, and Play plays again. Plants, each must fail it: (a) `makeViewModel` without `audioCaptureActivity:`; (b) the
  archive view model building its session with its own `AudioCaptureActivity()`.
- **Verify:** `B`, then `CAPTURE`; `grep -rn "AudioCaptureActivity\.shared\|AudioCaptureActivity = \.shared" Sources Tests`
  finds nothing.

### Step 3: Docs, full gates, live check

- `docs/architecture.md` § Archive preview playback: the session pauses on the context's signal, which the recorder
  sets; the wiring test. `docs/architecture-map.md`: gap 5 without `AudioCaptureActivity.shared`; gap 2 lists the
  signal among the context's defaults; a state-owner row for the recording signal.
- Move this plan file to the Trash.
- Rebase on origin/main if lane A has landed; resolve, rebuild.
- **Verify:**
  - The link check of the changed docs.
  - The full gates from Terminal.app.
  - A live check with `verify-niko-music-hub` (fixture archive): the archive arms the persistent player on selection;
    the Audio Recorder page opens idle; switching back keeps the archive's player state. Never press Start recording;
    the unit test covers the pause.

## Completion criteria

- No `AudioCaptureActivity.shared` in `Sources/` or `Tests/`; `AppComposition.make()` builds the one signal.
- The recorder and the archive get the signal through `ToolContext`; the wiring is checked by a test that plants (a)
  and (b) fail.
- Requirements 1 to 6 hold; existing tests pass unchanged except where a step or revision says why.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the owner. This plan is deleted.

## Follow-ups (not part of this plan)

- **`LiveProcessGroupRegistry.shared`**, the other half of gap 5: the helper process-group registry that quit reaps.
