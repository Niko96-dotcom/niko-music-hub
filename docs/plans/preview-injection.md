# Plan: Preview playback belongs to the archive view model, not to a singleton

**Status:** Approved under Niko's standing batch approval of 2026-10-24. In progress — see [Progress](#progress).  
**Date:** 2026-10-24  
**Source:** finding #11 of the 2026-10-22 architecture review ("Inject preview playback"). It closes open question 4
and the preview half of gap 5 in [architecture-map.md](../architecture-map.md).  
**Scope:** how the archive's preview playback (`ArchivePreviewSession`, its `ArchivePreviewPlayer`, the
`ArchivePlaybackCoordinator`) is created and reached by the view model and the views, in `FeatureArchiveBrowser`, one
line of `AppShellView`, their tests and docs. No change to what the person sees or hears: when playback starts, pauses
or stops, what the transport shows, the copy, the layout.

This plan keeps two kinds of statement apart. **Current** describes the code at `c51e10f`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit. Find a step's commit with
`git log --grep='(preview injection step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `c51e10f`: 2,900 passed, 0 failed, 8 skipped; Swift Testing 86 passed; no re-run |
| 1 Remove the playback coordinator | done | `git log --grep='(preview injection step 1)'` | strict build; preview suites 65 (1 new), 0 failures; with `clear()` not stopping the player the new reset test failed 5 assertions |
| 2 The view model and the views reach the session through the view model | done | `git log --grep='(preview injection step 2)'` | strict build; `FeatureArchiveBrowserTests` 667 (1 new), AppCore `*SourceTests` 99, 0 failures; plants (a) no `didSet` call and (b) session not told failed both the old regexes and the new test; (c) a dead Open action passed the old regexes and failed the new test |
| 3 Each view model creates its own session | not started | | |
| 4 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 2: `ArchivePreviewPlayback` goes in step 2, not step 3.** Once the view model's two resets call
   `previewSession.clear()`, the enum has no caller left; the one test that called it now resets through
   `clearSelection(stopPlayback: true)`, the view model's own path.
2. **Step 2: the remaining source test is renamed** `testArchiveCardPlayTargetsItsOwnSong`; it keeps only the card
   regex, and its comment names the interface test that took over the selection wiring.

## Terms

| Term | Meaning | Name in code |
| --- | --- | --- |
| Session | The archive's one playback owner: the loaded song and preview, the paused-transport rule, capture and route pauses | `ArchivePreviewSession` |
| Player | The session's AVFoundation engine: load, toggle, seek, metadata warmup | `ArchivePreviewPlayer`, `session.player` |
| Persistent player | The transport bar under every tool pane | `ArchivePersistentPlayerView` |
| Lifecycle reset | Stopping and clearing playback on purpose: a root change, or the loaded song is hidden or leaves the catalog | `ArchivePreviewPlayback.stopAll()` today |

## Current architecture (observed at `c51e10f`)

### One process-wide session, reached from 16 places

`ArchivePreviewSession.shared` (`ArchivePreviewSession.swift:9`) is the only session. It is reached by name from:

| File | Lines | Use |
| --- | --- | --- |
| `ArchivePreviewSession.swift` | 141 | `synchronizePreviewSelection()`: every write of `selectedSong` (`ArchiveBrowserViewModel.swift:169-172`) calls `.shared.followSelection` |
| `ArchiveBrowserViewModel+Selection.swift` | 108, 135 | stop when the selected song leaves the catalog; `audition(_:candidate:)` |
| `ArchiveBrowserViewModel+Metadata.swift` | 224 | stop when the loaded song is hidden |
| `ArchiveBrowserView.swift` | 8-9, 22-23, 609 | observes session and player; Space and Song menu play/pause and skip |
| `SongDetailView.swift` | 8 | play state, capture state |
| `ArchivePreviewRowView.swift` | 14 | alternate rows: loaded, playing, Compare |
| `SongCardView.swift` | 23 | list rows: "Playing" / "In player", play fallback |
| `ArchiveBoardView.swift` | 218 | board cards (`ArchiveBoardCardView`): play button state |
| `ArchivePersistentPlayerView.swift` | 6-7 | the transport bar, built by `AppShellView.swift:89` with no arguments |
| `ArchivePreviewPlayback.swift` | 8 | `stopAll()`, the lifecycle reset |

The session also keeps a private copy of the selection (`selectedSong`, `selectedSongAction`,
`ArchivePreviewSession.swift:30-31`) so that a pause can re-arm the transport to the selected song
(`followSelectionIfIdle`, `:64-85`). That copy is the session's own rule and stays; what changes is how it is fed.

### A coordinator that no longer coordinates anything

`ArchivePlaybackCoordinator.shared` (`ArchivePlaybackCoordinator.swift:6-12`) records the audible URL
(`beginPlayback`/`endPlayback`, six calls in `ArchivePreviewPlayer.swift:210, 218, 260, 267, 316, 468`) and, in
`stopAllPlayback()`, bumps `stopGeneration` when something is audible. Its only subscriber is the session
(`ArchivePreviewSession.swift:44-46`), which then calls `clear()`. Its only caller is `ArchivePreviewPlayback.stopAll()`,
which calls `ArchivePreviewSession.shared.clear()` right after (`ArchivePreviewPlayback.swift:7-8`). No view observes it.

It dates from when each row had its own player. Today production builds exactly one `ArchivePreviewPlayer`, the
session's (`ArchivePreviewSession.swift:33`; `ArchiveLiquidSurfaceSourceTests` keeps `ArchivePreviewPlayer()` out of the
rows and the detail). So "only one preview plays at a time" holds by construction, and `stopAll()` has the same effect
as `clear()` alone. The deletion test: delete the coordinator and no complexity reappears anywhere.

### Tests reset shared state by hand, and a regex pins the wiring

- `ArchivePreviewSessionTests` uses `.shared` in 7 tests, each with `defer { session.clear() }`.
- `SongCardInteractionTests:32-54` calls `ArchivePreviewPlayback.stopAll()` before each click and at the end.
- `ArchiveBoardPlaybackTests:31-35, 70-73` clears the shared coordinator's `activeURL` before testing it.
- `HubDesignContractSourceTests.swift:12-23` (`testArchivePausedTransportSelectionReachesItsSessionOwner`) checks
  three regexes over the source: the `selectedSong` `didSet` calls `synchronizePreviewSelection()`; the session file
  contains `ArchivePreviewSession.shared.followSelection(selectedSong)`; the board card's `playPreview()` is
  `onPlay?()`. The first two exist because there is no interface a test can call to check the wiring.

Problems:

- **Hidden dependency.** The view model, six views and the shell reach playback by name; nothing in an initializer
  says they depend on it (AGENTS.md bans `.shared` singletons).
- **No test isolation.** Every test that touches a view model shares one session; tests reset it by hand, and
  parallel tests or two archive windows would collide.
- **A redundant layer.** The coordinator adds a broadcast that duplicates `clear()`.

## Design A — the view model owns the session; views get it by initializer (chosen)

1. **Delete the coordinator (step 1).** The player no longer reports begin/end; the session drops its
   `stopGeneration` subscription; the lifecycle reset is `clear()`.
2. **The view model holds the session (steps 2 and 3).** `ArchiveBrowserViewModel` gets
   `let previewSession: ArchivePreviewSession`, created with the view model like its other owners
   (`vaultObservation`, `vaultOperations`, `mixdownAnalysis`). Every view-model use goes through it: selection
   (`synchronizePreviewSelection`), audition, the lifecycle resets. In step 2 the property is still
   `ArchivePreviewSession.shared` (the alias while the code migrates); step 3 makes it `ArchivePreviewSession()` and
   deletes `.shared` and `ArchivePreviewPlayback`.
3. **Views get it by initializer.** Views that already take the view model read `viewModel.previewSession`
   (`ArchiveBrowserView`, `SongDetailView`); leaf views take `@ObservedObject var session: ArchivePreviewSession` as a
   parameter (`SongCardView`, `ArchiveBoardCardView`, `ArchivePreviewRowView`), filled by their parent from the view
   model. `ArchivePersistentPlayerView` takes the view model: `init(viewModel:onOpenSong:)`, so
   `AppShellView.swift:89` passes the `archiveViewModel` it already holds. The session type stays internal.
4. **An interface test replaces the wiring regexes.** A test writes `selectedSong` directly, restores a route, and
   checks that the view model's session arms the paused transport and that its Open action returns to that view model.
   A second test checks that two view models have independent sessions.

`AppComposition` does not change: it already builds the one archive view model, which builds the one session.

## Design B — the composition creates the session; the environment carries it (not chosen)

The review's sketch: `AppComposition` creates a public `ArchivePreviewSession`, passes it to the view model's
initializer, and the shell sets it with `.environmentObject(_:)`; the views read `@EnvironmentObject`.

Why it is not chosen:

- **It splits one owner in two.** The session only works with the view model's selection and its Open action; neither
  lives without the other. Creating it in the composition adds a wiring step and hides nothing.
- **A missing object fails at runtime.** `@EnvironmentObject` crashes when a parent forgets it (each hosted view in
  `SongCardInteractionTests` would need it); an initializer parameter fails to compile. The project uses no
  `@EnvironmentObject` today, and AGENTS.md asks for collaborators through initializers.
- **More public surface and more shell edits.** The session type and initializer become public for the app target;
  `AppComposition`, `NikoMusicHubApp` or `AppShellView` change in more places, beside lane A's shell work.

B's advantage: no leaf view needs a new parameter, and the composition could hand the same session to a second
consumer. There is none today; if a second window needs one, the view model's initializer can take a session then.

## Comparison

| | A: the view model owns it | B: composition + environment |
| --- | --- | --- |
| Depth | The session keeps its interface; the coordinator goes | The same session; the coordinator could go too |
| Locality | Playback lives with the selection it follows | Created in the composition, used in the feature |
| Enforcement | Compiler: every view gets its session by parameter | Runtime: a missing environment object crashes |
| Test isolation | A fresh session per view model | A fresh session per test that builds one |
| Change surface | Feature files, one shell line | Feature files, public API, composition, shell |
| Risk | Low: same instance count in production | Low-medium: new idiom, runtime failure mode |

**Decision: A.** No ADR: the lasting part (the state owner and the seam) goes into [architecture.md](../architecture.md)
and [architecture-map.md](../architecture-map.md) in step 4.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Playback state, paused-transport rule, capture and route pauses | `ArchivePreviewSession.shared` | the view model's `previewSession` |
| One preview at a time | `ArchivePlaybackCoordinator.shared` (redundant) | the session's one player |
| Lifecycle reset | `ArchivePreviewPlayback.stopAll()` | `previewSession.clear()` |
| Feed selection to playback | `selectedSong` `didSet` → `.shared` | `selectedSong` `didSet` → `previewSession` |

### Interfaces

- **New:** `ArchiveBrowserViewModel.previewSession` (internal); `ArchivePersistentPlayerView.init(viewModel:onOpenSong:)`;
  a `session` parameter on `SongCardView`, `ArchiveBoardCardView`, `ArchivePreviewRowView`.
- **Removed:** `ArchivePreviewSession.shared`, `ArchivePlaybackCoordinator`, `ArchivePreviewPlayback`,
  `ArchivePersistentPlayerView.init(onOpenSong:)`.
- **Unchanged:** the session's methods and published state, `ArchivePreviewPlayer`'s interface (minus the coordinator
  calls), `AudioCaptureActivity`, every UI string.

### Dependency direction

No new module or module edge. The app target already imports `FeatureArchiveBrowser` and holds the view model.

## Behavior and compatibility requirements

1. **The person sees and hears the same.** [design-contract.md § Archive selection and persistent preview
   player](../design-contract.md#archive-selection-and-persistent-preview-player) holds unchanged: selection arms the
   paused transport without audio; playing audio survives browsing; a pause re-arms the selection; card Play auditions
   its own song; Space and the Song menu; recording blocks playback; unplug pauses; a root change or hiding or losing
   the loaded song stops and clears. The existing session, route, card, keyboard and source tests pass unchanged except
   where a step names the change.
2. **One session in the app.** Production builds one archive view model, so one session lives for the app's lifetime,
   as today. It is built in the view model's initializer (during `AppComposition.make()`) instead of at the first view
   body; both run at launch on the main actor.
3. **No singleton at the end.** No `ArchivePreviewSession.shared`, no coordinator. `AudioCaptureActivity.shared` stays
   (a follow-up: it is shared with the recorder feature).
4. **Compile-checked wiring.** Every view that shows playback gets the session through an initializer.
5. **The new wiring test is at least as strict as the regexes it replaces.** Plants that fail the regexes (no
   `didSet` call; the session not told) also fail the new test; the new test also fails when the Open action is
   broken, which the regexes do not see. The card-play regex stays.
6. **Lane A safety.** `AppComposition` unchanged; `AppShellView` changes on one line (`:89`).

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(preview injection step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `PREVIEW`: `T(ArchivePreviewSessionTests|ArchivePreviewRouteObserverTests|ArchiveBoardPlaybackTests|SongCardInteractionTests|ArchiveMiniPlayerMetadataCacheTests|ArchivePreviewSeekRelativeTests|ArchiveLiquidSurfaceSourceTests|ArchiveKeyboardFocusTests|ArchiveBoardSongsViewTests|HubDesignContractSourceTests|HubShellChromeSourceTests|SwiftUIStateOwnershipSourceTests)`
- `ARCHIVE`: `T(FeatureArchiveBrowserTests)` and the AppCore `*SourceTests`
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline

- The full gates passed on `c51e10f` (2,900 passed, 0 failed, 8 skipped; Swift Testing 86 passed). Record that
  instead of re-running.

### Step 1: Remove the playback coordinator

- Delete `ArchivePlaybackCoordinator.swift` (to the Trash). Remove its six calls from `ArchivePreviewPlayer`
  (`stop()` keeps clearing `activeURL` only when it is set) and the `stopGeneration` subscription from the session.
  `ArchivePreviewPlayback.stopAll()` calls only `ArchivePreviewSession.shared.clear()`. Update the `forceStop()`
  comment, which explains itself through the coordinator's broadcast.
- Tests: delete the two coordinator tests in `ArchiveBoardPlaybackTests` (the broadcast they check no longer exists;
  no view observed it). Add to `ArchivePreviewSessionTests`, with its own session: a lifecycle reset of a playing
  preview stops audio and clears the transport (`preview`, `songID`, `player.activeURL` nil; `isPlaying` false;
  `currentTime` and `duration` 0). Plant: `clear()` without `player.bind(url: nil)` fails it.
- **Verify:** `B`, then `PREVIEW`.

### Step 2: The view model and the views reach the session through the view model

- `ArchiveBrowserViewModel.previewSession`, still `ArchivePreviewSession.shared`. Switch every view-model use
  (`synchronizePreviewSelection`, `audition`, `reconcileSelectedSong`, `setSongHidden`, `clearSelection`,
  `clearRootBoundArchiveState`) to it; the two resets call `previewSession.clear()`.
- Views: `ArchiveBrowserView` and `SongDetailView` observe `viewModel.previewSession`; `SongCardView`,
  `ArchiveBoardCardView`, `ArchivePreviewRowView` take `session:` from their parents; `ArchivePersistentPlayerView`
  takes `viewModel:`; `AppShellView.swift:89` passes `archiveViewModel`. After this step `.shared` appears only in
  the view model's property.
- Tests: before the change, plant (a) the `didSet` without `synchronizePreviewSelection()` and (b)
  `synchronizePreviewSelection()` without the `followSelection` call; both fail
  `testArchivePausedTransportSelectionReachesItsSessionOwner`; restore. Then add the interface test
  (`ArchivePreviewSessionTests`): a direct `selectedSong` write and a restored `detail:` route arm the view model's
  session (song, title, preview, bound URL, no audio); the session's Open action selects that song and opens its
  detail. Remove the first two regexes from the source test, keep the card regex. Repeat plants (a) and (b), plus
  (c) the Open closure doing nothing: the new test fails each time. `SongCardInteractionTests` passes its own
  session to the views. `ArchiveLiquidSurfaceSourceTests` checks `previewSession.clear()` instead of
  `ArchivePreviewPlayback.stopAll`.
- `design-contract.md`: the session is the view model's (same rules); same commit as the guard change.
- **Verify:** `B`, then `PREVIEW` and `ARCHIVE`.

### Step 3: Each view model creates its own session

- `previewSession = ArchivePreviewSession()`. Delete `ArchivePreviewSession.shared` and `ArchivePreviewPlayback.swift`
  (to the Trash).
- Tests: `ArchivePreviewSessionTests` uses `model.previewSession` and drops the `defer { session.clear() }` that reset
  the shared session; tests that build their own session keep their own cleanup. New test: two view models; selecting
  and auditioning in one leaves the other's session empty. Plant: the alias back (`= .shared`) fails it.
- **Verify:** `B`, then `PREVIEW` and `ARCHIVE`; `grep -rn "ArchivePreviewSession\.shared\|ArchivePlaybackCoordinator\|ArchivePreviewPlayback" Sources Tests`
  finds nothing.

### Step 4: Docs, full gates, live check

- `docs/architecture.md`: a short "Preview playback" paragraph in the archive part (the session is the view model's;
  views get it by initializer; one player, so no coordinator). `docs/architecture-map.md`: the state-owner row, gap 5
  without the two preview singletons, open question 4 settled.
- Move this plan file to the Trash.
- **Verify:**
  - The link check of the changed docs.
  - The full gates from Terminal.app.
  - A live check with `verify-niko-music-hub` (`features/preview-playback.md`, fixture archive):
    1. Card Play on a board card: the persistent player shows that song and plays; the card shows its playing state.
    2. Select another card while playing: audio continues, the bar keeps the playing song.
    3. Pause, then select another card: the bar re-arms to the selected song without audio.
    4. Song detail: its player and an alternate row play, and Compare works.
    5. Relaunch: the app opens with no audio and no crash; selection and the bar behave as in 1-3.

## Completion criteria

- No `ArchivePreviewSession.shared`, no `ArchivePlaybackCoordinator`, no `ArchivePreviewPlayback` in `Sources/` or
  `Tests/`.
- Every view that shows playback gets the session by initializer; the view model owns the one session.
- The wiring is checked by an interface test that the plants in steps 2 and 3 fail.
- Requirements 1 to 6 hold; existing tests pass unchanged except where a step or revision says why.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the owner. This plan is deleted.

## Follow-ups (not part of this plan)

- **`AudioCaptureActivity.shared`.** The recorder and the archive share it; inject one instance through `ToolContext`
  (both features already receive the context).
- **The player's static metadata caches.** `ArchivePreviewPlayer`'s hook and duration caches are process-wide statics
  that tests clear by hand; with one player per session they could be the session's.
- **Route-observer cleanup.** `ArchivePreviewRouteObserver` never removes its CoreAudio listeners (they hold only a weak
  reference). One session per view model makes that visible in tests and in the in-process smoke; a `deinit` cleanup
  needs a Sendable registration store.
