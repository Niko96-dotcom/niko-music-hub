# Plan: Archive views state intent; the model owns page and gate rules

**Status:** Approved by Niko on 2026-10-23, including requirement 3. In progress — see [Progress](#progress).  
**Date:** 2026-10-23  
**Source:** finding #5 of the 2026-10-22 architecture review ("Views state intent; the model owns page and gate
rules"), the next open Strong finding after #1 to #4.  
**Scope:** the Archive Browser's page state (`viewMode`, `listShowsDetail`), the song detail's status-menu gate, and
the Undo of song-note edits. Views, the view model's navigation and selection extensions, the metadata editing
coordinator, their tests, one source guard, AGENTS.md and the docs. No change to the board cards' own gate, the
Vault rules, the metadata store or the design contract.

This plan keeps two kinds of statement apart. **Current** describes the code at `7204854`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed). Find a step's
commit with `git log --grep='(intent step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `7204854` (its commit message), no code commits since; no re-run |
| 1 Navigation intents | done | `git log --grep='(intent step 1)'` | strict build; `FeatureArchiveBrowserTests` 657 and AppCore `*SourceTests` 93, 0 failures |
| 2 Guard the page rule | done | `git log --grep='(intent step 2)'` | strict build; `ArchiveViewIntentSourceTests` 2 and every AppCore `*SourceTests` (95), 0 failures; a planted `viewModel.viewMode = .list` failed the guard at `ArchiveBoardView.swift:47`, then was removed |
| 3 One status gate in the song detail | done | `git log --grep='(intent step 3)'` | strict build; `FeatureArchiveBrowserTests` 658 and AppCore `*SourceTests` 96, 0 failures; the source test failed on the old gate; the Vault test shows card state `archiving`, block off, gate refusing |
| 4 Notes Undo in the coordinator | done | `git log --grep='(intent step 4)'` | strict build; `FeatureArchiveBrowserTests` 661 and AppCore `*SourceTests` 96, 0 failures; with the commit's Undo switched off, 4 tests failed (2 new, 2 autosave); 4 hand-written `registerMetadataUndo` calls left the tests, no expectation changed |
| 5 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 1: only `audition` moved.** `ArchivePreviewSession.swift`'s view-model extension also holds
   `synchronizePreviewSelection()`, which writes no page state. Moving it too broke
   `HubDesignContractSourceTests.testArchivePausedTransportSelectionReachesItsSessionOwner`, which pins it to that file,
   so it stays there, as the plan said.
2. **Step 4: the coordinator compares the merged song, not the catalog after the commit.** The view read
   `viewModel.songs` again after each commit. The coordinator's test host does not apply replacements to its song
   list, and reading the catalog back would rely on the host updating it at once. So `applyMetadataMerge` now runs
   through a private `mergeAndCommit` that also returns the merged song, and `commitNotes` compares it with the song
   the catalog held before.

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Page | Which Archive Browser page shows: board, board detail, list (with or without its compact detail), analytics | `viewMode`, `listShowsDetail` |
| Intent | A view's request, named for what the person wants ("back to the board"), that the view model turns into page state | `openSongDetail(_:)`, `setBrowseLayout(list:)`, `showAnalytics()`, `clearSelection(stopPlayback:)` |
| Status gate | Whether a song's workflow status may change now | `canMutateWorkflowStatus(for:)`; partial copies in views |
| File-action block | Whether Vault state blocks generic file actions and metadata edits for a song | `blocksGenericProjectVaultFileActions(for:)` |
| Notes | A song's display title, aliases and note | `virtualTitle`, `aliases`, `appNote` |
| Notes Undo | The "Edit Song Notes" Undo entry for a note edit | `registerMetadataUndo(...)` |

## Current architecture (observed at `7204854`)

### Page state is written from views

`viewMode` and `listShowsDetail` are `@Published var` on `ArchiveBrowserViewModel`. The view model writes them in its
intent methods (`+Navigation.swift`: `restoreNavigationRoute`, `setBrowseLayout(list:)`; `+Selection.swift`:
`openSongDetail(_:)`, `showAnalytics()`, `clearSelection(stopPlayback:)`) and in `audition(_:candidate:)`, a view-model
extension that sits in `ArchivePreviewSession.swift:138-153`. Five view sites write the state themselves:

| View site | Write | Intent it means |
| --- | --- | --- |
| `ArchiveAnalyticsView.swift:43` | `viewMode = .board` | back to the board |
| `ArchiveBoardView.swift:47` (empty state) | `viewMode = .list` | `setBrowseLayout(list: true)`, which exists |
| `ArchiveBrowserView.swift:91` (compact list detail) | `listShowsDetail = false`, then `clearSelection` | `clearSelection` already sets it to false (`+Selection.swift:125`) |
| `ArchiveBrowserView.swift:257` (Esc) | `viewMode = .board` from detail or analytics | back to the board |
| `ArchiveBrowserView.swift:359` (detail's Board button) | `viewMode = .board` | back to the board |

`477f9ae` fixed the same pattern for `showsBoardPage`: four view copies of one condition had drifted apart. No test or
check stops a new view write.

### Three copies of the status gate

| Where | Rule |
| --- | --- |
| `canMutateWorkflowStatus(for:)` (`+ProjectVault.swift:126-131`); used by the metadata coordinator's `canMutateStatus` gate, board drops (`ArchiveBoardColumnView.swift:84, 89`), the menu-bar Song commands (`ArchiveBrowserView.swift:435`), Done archive and restore | not blocked **and** `ProjectVaultCardWorkflowPolicy` allows the card state (`active`, `keepLocal`) |
| Board and list cards (`ArchiveBoardView.swift:221`, `SongCardView.swift:36`) | `ProjectVaultCardWorkflowPolicy` only |
| Song detail status menu (`SongDetailView.swift:191-194`) | not blocked only |

During an archive transfer the song's own folder is the transfer source, which the file-action block does not cover
(`ArchiveVaultObservation.swift:448-491`): the block is off, the card state is `archiving`. So the board refuses a
status change and the detail's status menu offers it. Choosing a status there does nothing:
`ArchiveMetadataEditingCoordinator.updateWorkflowStatus` returns at its `canMutateStatus` guard (`:294-300`) without a
message. (The review marked this "not checked at runtime"; the code path is as described.)

### Notes Undo is registered by the view

`SongDetailView` registers "Edit Song Notes" Undo five times (`flushMetadataDraftsIfEdited` `:755`,
`commitAllMetadata` `:789`, `commitVirtualTitle` `:823`, `commitAppNote` `:838`, `commitAliases` `:853`). Each copy
remembers the old values, calls a commit, reads `viewModel.songs` again, compares, and calls
`viewModel.registerMetadataUndo(...)` (`+Metadata.swift:88`, forwarding to the coordinator, `:231`). Workflow-status
Undo already lives in the coordinator: `updateWorkflowStatus` registers it after a commit that was not refused
(`:294-325`). The note commits are only called from `SongDetailView` in production, and every call there registers Undo.

Problems:

- **No locality for page rules.** A new page (or a change such as "Back clears the selection") must be found in views
  as well as in the view model.
- **A gate copy that is wrong today.** The detail offers status changes that the board and the coordinator refuse.
- **Undo needs a view.** Notes Undo can only be tested through `SongDetailView`'s private functions; the five copies
  must stay in step with the coordinator's commit rules by hand.

## Design A — intents, one gate, Undo with the commit (chosen)

1. **Navigation.** One new intent, `showBoard()`: from the board detail or analytics back to the board, keeping the
   selection (what the three `viewMode = .board` sites do today). The board's empty state calls
   `setBrowseLayout(list: true)`; the compact list detail calls only `clearSelection(stopPlayback: false)`.
   `audition(_:candidate:)` moves to `ArchiveBrowserViewModel+Selection.swift`. Then only `ArchiveBrowserViewModel*.swift`
   writes `viewMode` and `listShowsDetail`, and a source test keeps it so.

   ```swift
   /// Back to the board from its detail or from analytics. The selection stays,
   /// so the board highlights the song the person came from.
   func showBoard()
   ```

2. **Status gate.** `SongDetailView`'s status menu is disabled by `!viewModel.canMutateWorkflowStatus(for: liveSong)`,
   the gate the coordinator enforces. The metadata form and the collaborator section keep the file-action block,
   which is the coordinator's metadata gate (`isVaultBlocked`).

3. **Notes Undo.** The coordinator's note commits (`commitVirtualTitle`, `commitAppNote`, `commitAliases`,
   `applySongNotes`, `flushMetadataDrafts`) register "Edit Song Notes" Undo themselves when the outcome is not
   `.refused` and a note value changed, with the values the catalog held before the commit. `registerMetadataUndo`
   becomes private to the coordinator, and the view model's forward goes. `undoMetadata` commits without registering
   and then registers the redo, as today. The commits keep their `MetadataCommitOutcome` result: the form still keeps
   its drafts dirty on `.refused`.

## Design B — a page value with one writer and a detail capabilities value (not chosen)

Mirror `SongCatalog`: an `ArchivePage` value (board, detail, list, list detail, analytics) whose transitions are
mutating methods, held as `private(set) var page` and written only by one `navigate(_ intent:)` in
`ArchiveBrowserViewModel.swift`, so another writer does not compile. Add a `SongDetailCapabilities` value
(`canChangeStatus`, `canEditNotes`, `canEditCollaborators`) that the view model computes for the selected song and the
detail reads instead of calling gate functions.

Why it is not chosen:

- **Little to hide.** The page has two fields and about ten transitions, most of them one line in an existing intent.
  The deletion test moves a few `switch` statements back; nothing concentrates that the source guard does not already
  protect.
- **More churn for the same rule.** Navigation code in `+Navigation.swift` and `+Selection.swift` (and its history
  recording, which observes `$viewMode`) would move behind a new writer in the main file, and the 12 test writes of
  `viewMode` and `listShowsDetail` would need a seeding path.
- **A capabilities value can go stale.** Gates depend on Vault snapshots that change underneath the detail; a stored
  value must be recomputed on every snapshot change, while the views already read the live gate functions.

Revisit B if page transitions grow real rules (for example a route stack inside the archive), or if a second view
needs the whole set of detail gates.

## Comparison

| | A: intents + one gate + Undo with the commit | B: page value + capabilities value |
| --- | --- | --- |
| Depth | Existing intents gain one (`showBoard`); the coordinator's commits gain their Undo | New types whose interfaces are nearly as large as their bodies |
| Locality | Page writes in `ArchiveBrowserViewModel*.swift`; one status gate; Undo next to the commit | The same, plus a second home for gate results |
| Enforcement | Source test (page writes), source test (detail gate), coordinator tests (Undo) | Compiler for page writes; tests for the rest |
| Caller knowledge | Call the intent; read the gate function the coordinator uses; commit and ignore Undo | Call `navigate(_:)`; read capabilities that must be fresh |
| Risk | Low: small edits, behavior kept except the gate fix | Medium: navigation code moves, history recording must follow |

**Decision: A.** It removes every view write of page state, the wrong gate copy and the five Undo copies with the least
new structure. No ADR is needed; the lasting part goes into [architecture.md](../architecture.md) in step 5.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Turn a view's request into page state | view model intents, plus five view sites | view model intents only (`ArchiveBrowserViewModel*.swift`) |
| May a song's status change now | `canMutateWorkflowStatus`, plus a shorter copy in the detail | `canMutateWorkflowStatus` (cards: see Follow-ups) |
| Register notes Undo | `SongDetailView`, five copies | `ArchiveMetadataEditingCoordinator`, with the commit |
| Register status Undo | `ArchiveMetadataEditingCoordinator` | unchanged |
| Keep drafts dirty on a refused save | `SongDetailView` | unchanged: the view, from the commit's outcome |

### Interfaces

- **New:** `ArchiveBrowserViewModel.showBoard()`.
- **Moved:** `audition(_:candidate:)` from `ArchivePreviewSession.swift` to `ArchiveBrowserViewModel+Selection.swift`.
- **Removed:** `ArchiveBrowserViewModel.registerMetadataUndo(...)`; `ArchiveMetadataEditingCoordinator.registerMetadataUndo`
  becomes `private`.
- **Changed:** the coordinator's note commits register their own Undo (same signatures and outcomes).
- **Unchanged:** `viewMode`, `listShowsDetail` (still `@Published`; the setter stays internal because the view model's
  navigation lives in several extension files and tests seed it), `canMutateWorkflowStatus(for:)`,
  `MetadataCommitOutcome`, the navigation history routes.

### Dependency direction

No new type, module or module edge.

## Behavior and compatibility requirements

1. **Same pages.** Every view action lands on the same page as today: Back and Esc from detail or analytics reach the
   board with the selection kept; the empty board's list button opens the list; the compact list's "Back to Songs"
   clears the selection and closes the detail.
2. **Same history.** Navigation history records the same routes (`board`, `detail:<id>`, `list`, `analytics`).
3. **Status menu (behavior change; needs Niko's OK).** The song detail's status menu is disabled whenever the board
   refuses a status change for that song: during an archive transfer, while archived, restoring or needing attention,
   and when the file-action block applies. Today it stays enabled in the first four cases and a choice does nothing.
4. **Same Undo stack.** One "Edit Song Notes" Undo entry per note edit that changed a value and was not refused (also
   `savedWithWarning`, as today); none when nothing changed or the save was refused; Undo restores the old values and
   offers Redo; the draft flush on leaving a detail registers Undo as today.
5. **Same refusals.** The note commits keep their outcomes and warnings; the form keeps its drafts dirty on `.refused`.
6. **Out of scope:** the board and list cards' shorter gate (Follow-ups), Undo for collaborator assignment, the
   menu-bar Song commands (they already use `canMutateWorkflowStatus`).

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(intent step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `ARCH`: `T(FeatureArchiveBrowserTests)` plus every `*SourceTests` in `AppCoreTests`
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline

- The full gates passed on `7204854` (see its commit message). Record that instead of re-running, unless code
  commits landed since.

### Step 1: Navigation intents

- Add `showBoard()` in `+Navigation.swift`. Route `ArchiveAnalyticsView.swift:43` and `ArchiveBrowserView.swift:257,
  359` through it; `ArchiveBoardView.swift:47` through `setBrowseLayout(list: true)`; drop the redundant
  `listShowsDetail = false` at `ArchiveBrowserView.swift:91`.
- Move `audition(_:candidate:)` into `+Selection.swift` unchanged.
- Tests (`ArchiveNavigationHistoryTests`): `showBoard()` from the detail keeps the selection and records `board`;
  from analytics it records `board`; on the board it records nothing new.
- **Verify:** `B`, then `ARCH`.

### Step 2: Guard the page rule

- Add `Tests/AppCoreTests/ArchiveViewIntentSourceTests.swift`, `testOnlyTheViewModelWritesThePage`: over
  `Sources/FeatureArchiveBrowser` (comment-stripped), an assignment to `viewMode` or `listShowsDetail` appears only in
  `ArchiveBrowserViewModel*.swift`. Add a detector self-test (`viewModel.viewMode = .board` hits;
  `viewModel.viewMode == .board` and `case .board` do not).
- Plant a `viewModel.viewMode = .list` in a view, see the test fail at the right file, remove it.
- Add the AGENTS.md rule row: "Archive views state intent (`openSongDetail`, `showBoard`, `setBrowseLayout`,
  `clearSelection`, …); only `ArchiveBrowserViewModel*.swift` writes `viewMode` and `listShowsDetail`" |
  `ArchiveViewIntentSourceTests`.
- **Verify:** `B`, then every `*SourceTests`.

### Step 3: One status gate in the song detail

- `SongDetailView.swift:191-194`: `.disabled(!viewModel.canMutateWorkflowStatus(for: liveSong))`.
- Tests:
  - `ArchiveVaultObservationTests`: with a transfer in `copyingToArchiveStaging` for a song (the existing
    `makeTransferSnapshot` fixture), `blocksGenericProjectVaultFileActions` is false and `canMutateWorkflowStatus` is
    false: the shorter rule would offer the change.
  - `ArchiveViewIntentSourceTests.testSongDetailStatusMenuUsesTheStatusGate`: the `.disabled` modifier of the detail's
    `ArchiveWorkflowStatusMenu` calls `canMutateWorkflowStatus`, not `blocksGenericProjectVaultFileActions`.
- **Verify:** `B`, then `ARCH`.

### Step 4: Notes Undo in the coordinator

- In `ArchiveMetadataEditingCoordinator`, the note commits take the catalog's values before the commit (from
  `host.currentSongs()`), commit, and register Undo when the outcome is not `.refused` and a value changed. One
  private helper does this for all five entry points. `undoMetadata` uses the commit without Undo and registers the
  redo. `registerMetadataUndo` becomes `private`.
- Remove `ArchiveBrowserViewModel.registerMetadataUndo` and the Undo code in `SongDetailView`'s five functions (they
  keep the outcome check and the draft sync).
- Tests (`ArchiveMetadataEditingOwnerTests`, with an injected `UndoManager`): a changed title registers one Undo named
  "Edit Song Notes" and Undo restores it; a refused commit and an unchanged commit register nothing; Undo then Redo
  round-trips; `flushMetadataDrafts` registers Undo. Update `SongMetadataDraftAutosaveTests` and the owner tests that
  called `registerMetadataUndo` by hand (record each changed expectation as a revision).
- **Verify:** `B`, then `ARCH`.

### Step 5: Docs, full gates, live check

- `docs/architecture.md`: in "Archive metadata editing ownership", notes Undo now registers with the commit; add a short
  "Archive page state" paragraph (intents, the source guard). `docs/architecture-map.md`: the state-owner row for the
  archive page and the rule row in "Intended structure".
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - A live check with `verify-niko-music-hub`, in an isolated archive run:
    1. Open a song detail, press Esc: the board shows with that song highlighted. Open it again, press the detail's
       Board button: the same.
    2. Open analytics and leave it with its board button and with Esc: the board shows.
    3. List view below the split breakpoint, open a song, "Back to Songs": the list shows with no selection.
    4. Change a song's display title in the detail, Save metadata, then Edit > Undo "Edit Song Notes": the old title
       is back on the card and in the detail; Edit > Redo restores the new one.
    5. Status menu during an archive transfer: needs a Vault transfer held in progress (`features/project-vault.md`).
       Drive it if the run can hold one; otherwise record why not (step 3's tests cover the gate).

## Completion criteria

- No view writes `viewMode` or `listShowsDetail`; the source test enforces it, and the AGENTS.md row names it.
- The song detail's status menu uses `canMutateWorkflowStatus`, and requirement 3 is approved.
- Notes Undo is registered only inside `ArchiveMetadataEditingCoordinator`; its tests run without a view.
- Requirements 1, 2, 4 and 5 hold; existing tests pass, edited only where they registered Undo by hand.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the owners. This plan is deleted.

## Follow-ups (not part of this plan)

- **Card gate.** Board and list cards use only the card-state policy. When the file-action block applies while the card
  state allows changes, a card still offers a status change that the coordinator refuses. From the code: a transfer in
  state `superseded` on a song that keeps its Active folder maps to card state `active`, while the block applies
  (`ProjectVaultPresentation.swift:361-386`, `ArchiveVaultObservation.swift:485-486`). One fix: let the card presentation carry the full gate, built where the presentation is built.
- **Silent refusal.** `updateWorkflowStatus` returns without a message when `canMutateStatus` refuses. With every menu
  gated this should not be reachable from the UI; a refusal sentence would still help.
