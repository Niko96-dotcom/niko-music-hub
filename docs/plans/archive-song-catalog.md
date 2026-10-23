# Plan: One writer for the archive song catalog

**Status:** Approved by Niko on 2026-10-23, including B1 to B6. In progress — see [Progress](#progress).  
**Date:** 2026-10-23  
**Source:** finding #1 of the 2026-10-22 architecture review ("Give the archive catalog one writer"), the first open
Strong finding after #2 (footer), #3 (Keep Local) and #4 (tool output) were done.  
**Scope:** the in-memory song lists of `ArchiveBrowserViewModel` (`scannedSongs`, `songs`, `songsByID`), their seven
writers, the follow-up work a catalog change causes, the archive tests that seed the catalog, one benchmark script and
the docs. No change to scanning, the cached index format, metadata storage, Vault projection rules, views or the
design contract.

This plan keeps two kinds of statement apart. **Current** describes the code at `2570ffa`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed). Find a step's
commit with `git log --grep='(catalog step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `b04cc55` (code equal to `2570ffa`), no re-run; 10k data prepared (`BAKEOFF_NAME=catalog-writer`, 6,958 songs seeded in the database) |
| 1 `SongCatalog` and its tests | done | `git log --grep='(catalog step 1)'` | strict build; `SongCatalogTests` 9, 0 failures |
| 2 Storage moves into `SongCatalog` | done | `git log --grep='(catalog step 2)'` | strict build; `FeatureArchiveBrowserTests` 642 and AppCore `*SourceTests` 93, 0 failures; no test edited |
| 3 Scan and cache load through one writer | done | `git log --grep='(catalog step 3)'` | strict build; `FeatureArchiveBrowserTests` 643 and AppCore `*SourceTests` 93, 0 failures; the new B1 test failed with an unprojected cache load, then passed |
| 4 Vault reprojection and New Song | done | `git log --grep='(catalog step 4)'` | strict build; `FeatureArchiveBrowserTests` 646 and AppCore `*SourceTests` 93, 0 failures; B2 and B4 tests failed with the old behavior planted, then passed |
| 5 Metadata edits and collaborator removal | done | `git log --grep='(catalog step 5)'` | strict build; `FeatureArchiveBrowserTests` 650 and AppCore `*SourceTests` 93, 0 failures; B3 and B6 tests failed with the old behavior planted, then passed |
| 6 Root reset and per-song caches | not started | | |
| 7 Tests seed through the writer; the old writers go | not started | | |
| 8 Docs, full gates, benchmark, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 3: repair sync and index persist run per edit, not per change.** The plan's table ran every follow-up only
   for a non-empty change. But an unchanged rescan still syncs the repair state (the scan's metadata load can change
   the corrupt-row gate) and persists the index (it carries the scan date). So `applyCatalogEdit` runs those two by
   edit kind, even for an empty change; the rest runs only for a non-empty change.
2. **Step 3: the per-song cache step skips songs new to the catalog.** The scan's loop also looked at new songs, which
   cannot have a cache entry; it only cancelled the selected song's analysis in flight and wrote two `@Published`
   dictionaries per song. Run for a cache load into an empty catalog, that would be 20,000 publishes. New songs are
   skipped. Mixdown entries are pruned when the change removes songs, not on every visible change (only removed
   songs can leave stale entries once every write goes through `applyCatalogEdit`).
3. **Step 3: the scan records its persistence warning before the catalog write.** It used to come after the browse
   recompute. It still comes before the repair-state sync, which is the order that matters for the footer.
4. **Step 4: New Song saves the new song's metadata before the catalog write.** `persistUserMetadata` can mark rows
   corrupt, so the repair-state sync must follow it; the sync now runs inside `.add`. `SongCatalog` gained
   `scannedAdding(_:)` (the "add by title" rule, pure and tested), and `rebuildProjectVaultCatalog()` is gone a step
   early: no test called it.
5. **Step 5: an edit that moves the selected song out of the filter deselects it, as today.** The plan said the
   edited song stays selected. A probe on the step 4 code showed the opposite: the browse recompute inside
   `mutateCatalog` clears the selection first, and `replaceSong` re-selected only a song that was still selected. So
   `.replace` needs no selection step of its own; requirement 5, the follow-up table and the live check now describe
   today's rule, and `ArchiveCatalogEditTests` pins both cases.

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Catalog | The songs the archive browser holds in memory | `scannedSongs`, `songs`, `songsByID` on the view model |
| Scan baseline | What the roots' scan or the cached index found, without archived Vault paths. The index persist writes this list | `scannedSongs` |
| Visible list | The baseline plus archive-only Vault projections when "Show archived" is on. Views read it | `songs` |
| Projection | Baseline in, (clean baseline, visible list) out, from the Vault snapshots | `ArchiveVaultObservation.projectCatalog` |
| Edit | One of the six ways the catalog is written | the seven writers below |
| Change | What an edit changed: the visible list, the baseline, the changed songs with their old values, the removed IDs | partly `changedSongs(in:)` and `heldBefore` in the scan apply |
| Follow-up | Work a change causes: Vault card cache, publish, browse recompute (with selection), intelligence, analytics, per-song caches, index persist | `songs.willSet`, `mutateCatalog`, hand-written calls in each writer |
| `ArchiveCatalogCoordinator` | Scan, cached index and metadata I/O (named `catalog` in code). Not the in-memory catalog; this plan does not change it | `catalog` |

## Current architecture (observed at `2570ffa`)

The catalog is three stored properties of `ArchiveBrowserViewModel`:

- `@Published var songs` with a `willSet` that rebuilds `songsByID` and the Vault card cache before the publish
  (`ArchiveBrowserViewModel.swift:57-73`).
- `var scannedSongs` (`:307`), not published.
- `private var songsByID` (`:73`), read by `liveSong(id:)`, `heldSong(id:)` and `changedSongs(in:)`.

Seven code paths write them. Each one decides on its own which follow-ups to run:

| Writer | Where | Projection | Follow-ups it runs | What it misses or repeats |
| --- | --- | --- | --- | --- |
| Cache load | `+Scan.swift:88-126` (write `:114-117`) | none | `mutateCatalog`, repair sync | Writes the cache list into both lists without the Vault projection |
| Scan apply | `+ScanHost.swift:6-103` | yes | equality short-cut, `mutateCatalog`, selection, per-song cache invalidation and prune, repair sync, index persist, Vault snapshot refresh | The unchanged branch (`:27-32`) repeats part of `mutateCatalog` by hand |
| Vault rebuild | `+ProjectVaultCatalog.swift:11-18`, called from 8 places (`+ProjectVault.swift`, `+Roots.swift`, `createNewSong`) | yes | equality short-cut, `mutateCatalog` | No index persist, although the projection can change the baseline; no per-song cache prune |
| `replaceSong` | `+Metadata.swift:335-356`, called by the metadata coordinator (`ArchiveMetadataEditingCoordinator.swift:425`, `:519`) and collaborator removal | — | `mutateCatalog`, then re-selects the edited song | Publishes `songs` even when nothing changed |
| New Song | `+Metadata.swift:253-296` | through a second write | `mutateCatalog` twice (insert, then `rebuildProjectVaultCatalog`), repair sync, index persist | Two catalog writes, two browse recomputes |
| Root reset | `clearRootBoundArchiveState`, `+Scan.swift:40-81` | — | none; sets `songs = []` (`:52`) and `scannedSongs = []` (`:67`) among 37 statements, clears per-song caches by hand | Outside `mutateCatalog` |
| Collaborator removal | `+Collaborators.swift:200-205` | — | `replaceSong` once per song | N browse recomputes, N intelligence refreshes |

Other facts the design depends on:

- `mutateCatalog(_:)` (`+Browse.swift:24-34`) is the shared follow-up: browse recompute, intelligence refresh, analytics
  refresh while analytics is open. `applyScanFailure` also uses it without a catalog change (`+ScanHost.swift:105-113`).
  `ArchiveScanHost` requires it (`ArchiveScanOrchestrator.swift:30`), but the orchestrator never calls it.
- The browse recompute reconciles the selection and clears a selected song that left the filtered list
  (`+Browse.swift:130-135`). `replaceSong` re-selects the edited song only while it is still selected, so an edit
  that moves the selected song out of the current filter deselects it (checked at runtime, revision 5).
- The projection removes archived paths from the baseline and adds archive-only songs when they are shown
  (`ArchiveVaultObservation.swift:292-339`). It can read the metadata store, so it stays outside a pure value type.
- The delayed index persist writes the baseline (`ArchiveMetadataEditingCoordinator.swift:452`).
- Performance work from 19 to 21 October lives in these paths: `equalsConcurrently` short-cuts, sharing unchanged
  `Song` values with the held baseline (`SongCatalogDeduplicator.sharingUnchangedValues`), looking only at changed
  songs for per-song caches, and `OffMainRelease` of discarded arrays (`ArchiveScanOrchestrator.swift:235-236`).
- Tests seed the catalog by writing the fields: `.songs` 103 times and `.scannedSongs` 33 times, in 21 files. Every
  `scannedSongs` write is paired with an equal `songs` write. `script/performance/archive-ui.swift:150-151` does the
  same.

Problems:

- **No locality.** A new per-song derived value (for example waveform peaks) must be hooked into seven writers and the
  root reset, and someone must check by hand that cache load and the Vault rebuild reach it.
- **Silent gaps.** Cache load skips the projection; the Vault rebuild skips the index persist and the per-song cache
  prune. Each gap is small today; each new follow-up can add another.
- **Wasted work.** Collaborator removal recomputes the browse results once per song; New Song writes the catalog twice.
- **Tests can build impossible states.** A test can set `songs` without a baseline, which no production path produces.

## Design A — `SongCatalog` value type and one writer on the view model (chosen)

Two parts with different jobs:

1. **`SongCatalog`** (new, `Sources/FeatureArchiveBrowser/SongCatalog.swift`): a value type that owns the two lists and
   the ID index, and computes what an edit changed. Pure: no I/O, no Vault, no main actor. Its lists are `private(set)`.

   ```swift
   /// The songs the archive browser holds: the scan baseline and the visible list.
   /// `ArchiveBrowserViewModel.applyCatalogEdit(_:)` is its only writer.
   struct SongCatalog: Sendable {
       /// What the scan or the cached index found, without archived Vault paths.
       /// The index persist writes this list.
       private(set) var scanned: [Song] = []
       /// The baseline plus archive-only Vault projections when they are shown.
       private(set) var visible: [Song] = []

       func song(id: String) -> Song?
       /// The incoming songs that are new or differ from the visible list.
       func changedSongs(in incoming: [Song]) -> [Song]
       /// Unique by ID, with every unchanged song sharing the held baseline value
       /// (keeps one copy of an unchanged 10,000-song catalog).
       func sharingHeldValues(_ incoming: [Song]) -> [Song]

       /// Replaces both lists. An equal list stays as held; equal lists give an empty change.
       mutating func replaceAll(scanned: [Song], visible: [Song]) -> SongCatalogChange
       /// Replaces songs by ID in both lists. A song the baseline lacks is appended to it,
       /// unless `isArchiveOnly` says it is a Vault projection.
       mutating func replace(_ songs: [Song], isArchiveOnly: (Song) -> Bool) -> SongCatalogChange
       mutating func removeAll() -> SongCatalogChange
   }

   struct SongCatalogChange: Sendable {
       var visibleChanged: Bool
       var scannedChanged: Bool
       /// Visible songs that are new or differ, each with the value held before (nil when new).
       var changed: [(before: Song?, after: Song)]
       var removedIDs: Set<String>
       var isEmpty: Bool { !visibleChanged && !scannedChanged }
   }
   ```

2. **`applyCatalogEdit(_:)`** on the view model, in `ArchiveBrowserViewModel.swift` next to the stored
   `private(set) var songCatalog`. It is the only code that can write the catalog, because `private(set)` limits the
   setter to that file. It runs the projection where an edit needs it, writes `SongCatalog`, and runs the follow-ups
   from one table.

   ```swift
   enum SongCatalogEdit {
       case load([Song])     // cached index at launch; tests seed through this too
       case rescan([Song])   // scan result: dedupe, share held values, project
       case reproject        // Vault snapshots, "Show archived", Vault settings, roots
       case replace([Song])  // metadata edits and collaborator removal, one batch
       case add(Song)        // New Song: inserted into the baseline by title, then projected
       case clear            // root change
   }

   /// The catalog's only writer. Returns the change so a writer can do work only it knows
   /// about (the scan: diagnostics, status, announcement, Vault snapshot refresh).
   @discardableResult
   func applyCatalogEdit(_ edit: SongCatalogEdit) -> SongCatalogChange
   ```

   Follow-ups, run once per non-empty change, in this order:

   | Follow-up | When | Today |
   | --- | --- | --- |
   | Rebuild the Vault card cache for the new visible list, then `objectWillChange.send()`, then store | visible list changed | `songs.willSet` |
   | Browse recompute (it reconciles the selection), intelligence refresh, analytics refresh while open | any change | `mutateCatalog` |
   | Invalidate mixdown analysis and the CPR plugin summary of changed songs whose main preview or effective CPR changed; drop removed IDs; restart the selected song's analysis or plugin list when invalidated | any change | scan apply only; root reset by hand |
   | Repair-state sync | `.load`, `.rescan`, `.add` | the same writers |
   | Index persist now (`scheduleIndexPersist(afterNanoseconds: 0)`) | `.rescan`, `.add`, and `.reproject` when the baseline changed | scan and New Song only |

   Not in the table, on purpose: `.replace` leaves the index persist to `ArchiveMetadataEditingCoordinator`, which owns
   delayed persistence (collaborator removal keeps its debounced call); `.load` persists nothing (the cache is the
   source); `.clear` persists nothing (`metadataEditing.clearForRootChange()` cancels pending writes).

What stays with each writer: the scan keeps its diagnostics, status line, warnings, announcement, Vault snapshot
refresh and its unchanged short-cut (an empty change with unchanged skipped entries refreshes intelligence and
analytics only); cache load keeps its freshness guards and integrity gate; New Song keeps folder creation, metadata
merge, selection and opening; the root reset keeps its 35 statements that are not the catalog.

Read access does not change for views: `songs` and `scannedSongs` stay as read-only computed properties
(`songCatalog.visible`, `songCatalog.scanned`), and `liveSong(id:)`, `heldSong(id:)`, `changedSongs(in:)` read the
catalog.

## Design B — an `ArchiveCatalogModel` owner object (not chosen)

A `@MainActor final class ArchiveCatalogModel: ObservableObject`, built like `ArchiveVaultObservation` and
`ArchiveMetadataEditingCoordinator`: it owns the lists, runs the projection itself (with the Vault observation, the
metadata store, the collaborators and the "Show archived" flag injected), and reports each change to the view model
through a host closure. The view model re-emits its publishes and runs the follow-ups in that closure.

Why it is not chosen:

- **The follow-ups still live in the view model.** Browse results, selection, per-song caches and the index persist are
  view-model state. B moves the write into another object and calls back for the rest, so a reader follows each edit
  through two objects and a closure instead of one function.
- **A wider interface for the same writers.** The projection needs four inputs from the view model; "Show archived"
  would move or be read through a closure. The host contract and the publish bridge add wiring that A does not need.
- **Publish order gets harder.** Today the card cache is rebuilt before `songs` publishes. With B the rebuild, the
  owner's publish and the view model's re-emit cross two objects.
- **Deletion test.** Deleting B's class moves the lists and one projection call back into the view model; little
  complexity concentrates in it beyond what `SongCatalog` already holds in A.

Revisit B if the projection gets a second user, or if the archive view model is split into smaller owners
(finding #7 or a later review).

Also considered: no new type, only `private(set)` on `songs` and `scannedSongs` and one writer in the main file. Not
chosen: the change computation and the replace rules would be testable only through a whole view model, and the main
file would hold the list rules too. `SongCatalog` makes those rules testable in isolation.

## Comparison

| | A: `SongCatalog` + `applyCatalogEdit` | B: `ArchiveCatalogModel` owner |
| --- | --- | --- |
| Depth | Small: six edit cases over projection, equality short-cuts, value sharing, change computation and all follow-ups | Intent methods over the lists and projection, plus a host contract and a publish bridge |
| Locality | Lists and change rules in one value type; follow-ups in one function | Lists in the owner; follow-ups in a host closure in the view model |
| Caller knowledge | Pick an edit; read the change if needed | The same, plus the owner's lifetime and its bridge |
| Enforcement | The compiler: `private(set)` on `songCatalog` and on the lists | `private(set)` in the owner; the bridge can still be bypassed by re-emits |
| Tests | `SongCatalog` alone, plus one view-model test per edit | The owner with fakes, plus the host |
| Risk to the 10k work | Low: same short-cuts, same order | Higher: publish order across objects |

**Decision: A.** It gives the catalog one writer that the compiler enforces, one table of follow-ups, and testable list
rules, with the least new wiring. No ADR is needed. The lasting rationale goes into
[architecture.md](../architecture.md) in step 8.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Hold the baseline, the visible list and the ID index | the view model, three properties | `SongCatalog` (`songCatalog` on the view model) |
| Decide what an edit changed (changed songs with old values, removed IDs) | scan apply only | `SongCatalog` |
| Keep held values when equal; share unchanged song values | scan apply and `songs.willSet` | `SongCatalog` |
| Run the projection for an edit | each writer that remembers it | `applyCatalogEdit` |
| Run the follow-ups of a change | each writer, `mutateCatalog`, `songs.willSet` | `applyCatalogEdit`, one table |
| Scan-only, cache-only and New-Song-only work | the writer | unchanged: the writer |
| Projection rules | `ArchiveVaultObservation` | unchanged |
| Index persist timing for metadata edits | `ArchiveMetadataEditingCoordinator` | unchanged |

### Interfaces

- **New:** `SongCatalog`, `SongCatalogChange` (`Sources/FeatureArchiveBrowser/SongCatalog.swift`); `SongCatalogEdit` and
  `applyCatalogEdit(_:)` (`ArchiveBrowserViewModel.swift`). All `internal` to `FeatureArchiveBrowser`.
- **Removed:** the stored `songs`, `scannedSongs` and `songsByID`; `mutateCatalog(_:)` and its `ArchiveScanHost`
  requirement; `replaceSong(_:)`; `rebuildProjectVaultCatalog()` (its callers use `.reproject`).
- **Changed:** `songs` and `scannedSongs` become read-only computed properties. `ArchiveMetadataEditingHost.applyReplacement`
  calls `applyCatalogEdit(.replace([song]))`.
- **Unchanged:** `applyCatalogScanUpdate(_:roots:)` (the benchmark harness calls it and must build against both
  commits), `ArchiveScanHost.scannedSongs`, `ArchiveVaultObservation.projectCatalog`, `ArchiveCatalogCoordinator`,
  the views.

### Dependency direction

```text
ArchiveBrowserViewModel ──► SongCatalog ──► NikoMusicCore (Song, SongCatalogDeduplicator)
        └──► ArchiveVaultObservation (projection), ArchiveMetadataEditingCoordinator (persist)
```

No new module or module edge. `SongCatalog` imports only Foundation and NikoMusicCore.

## Behavior and compatibility requirements

1. **Same lists.** After every edit, the baseline and the visible list equal what today's writer produces, except B1
   below.
2. **Card cache before publish.** The Vault card cache is rebuilt before the view model publishes a new visible list,
   so a card never reads a stale cache.
3. **No work for no change.** An edit that changes neither list publishes nothing from the catalog and recomputes
   nothing.
4. **The 10k work survives.** Equality short-cuts, value sharing before the projection (the scan keeps today's order:
   dedupe and share against the held baseline, then project), per-song work only for changed songs, and
   `OffMainRelease` stay. Step 8 measures it.
5. **Selection.** Every edit keeps today's rule: the browse recompute updates a selected song to its new value and
   clears a selection that left the filtered list (revision 5).
6. **Index persist reads the baseline,** as today.
7. **Unchanged contracts.** `applyCatalogScanUpdate(_:roots:)`, the metadata coordinator's host closures (reads stay
   `currentSongs`/`currentScannedSongs`), the views, `ArchiveScanHost.scannedSongs`.
8. **Intended behavior changes** (each invisible to the user or a fix; each gets a test):
   - **B1. Cache load is projected.** On a normal launch the Vault snapshots are not loaded yet when the cache
     arrives, so the projection changes nothing. When they are, the list already matches what the next Vault rebuild
     shows.
   - **B2. A Vault reprojection that changes the baseline persists the index,** so the cache drops archived paths at
     once instead of at the next scan.
   - **B3. Collaborator removal is one edit:** one browse recompute, one intelligence refresh, one analytics refresh
     (today one per song).
   - **B4. New Song is one edit** (today two writes and two recomputes).
   - **B5. Per-song caches follow one rule for every edit.** For example, hiding archived projects drops their mixdown
     and plugin results; showing them again analyzes on selection, as for any song.
   - **B6. Replacing a song with an equal value publishes nothing** (today `replaceSong` always publishes).
9. **Out of scope:** the non-catalog properties of the root reset, renaming `ArchiveCatalogCoordinator`, moving the
   projection, finding #7 (who writes the music roots), the Vault presentation cache itself.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(catalog step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `ARCH`: `T(FeatureArchiveBrowserTests)` (the whole archive suite, about 630 tests) plus every `*SourceTests` in
  `AppCoreTests`
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline

- The full gates passed on `b04cc55`, whose code equals `2570ffa` (see the `2570ffa` commit message). Record that
  instead of re-running, unless code commits landed since.
- Prepare the 10k synthetic archive once: `BAKEOFF_NAME=catalog-writer script/bakeoff/app.sh prepare 10k`
  (gitignored `bakeoff-data/` and `BAKEOFF_NAME`). Build the baseline benchmark binary:
  `script/performance/build-commit-binaries.sh base 2570ffa launch`.

### Step 1: Add `SongCatalog` and its tests (not wired)

- Add `Sources/FeatureArchiveBrowser/SongCatalog.swift` with the interface above.
- Add `Tests/FeatureArchiveBrowserTests/SongCatalogTests.swift`:
  - **Equal lists:** `replaceAll` with equal lists returns an empty change.
  - **Change:** a changed and a new song appear in `changed` with their old value (nil when new); a missing song
    appears in `removedIDs`; `scannedChanged` and `visibleChanged` are independent.
  - **Index:** `song(id:)` finds visible songs, including archive-only projections, and not removed ones.
  - **Replace:** replaces in both lists; appends a baseline-missing song to the baseline unless `isArchiveOnly`; leaves
    the visible list unchanged for a song it does not hold; an equal replacement gives an empty change.
  - **Sharing:** `sharingHeldValues` dedupes by ID and returns the held value for every unchanged song.
  - **Remove all:** every visible ID is in `removedIDs`.
- **Verify:** `B`, then `T(SongCatalogTests)`.

### Step 2: Storage moves into `SongCatalog` (no behavior change)

- The view model stores `private(set) var songCatalog = SongCatalog()`. `songs`, `scannedSongs` and `songsByID` stop
  being stored. `liveSong`, `heldSong` and `changedSongs(in:)` read `songCatalog`.
- `songs` and `scannedSongs` keep **transitional** setters, marked `// Transitional: removed in catalog step 7`. They
  call `replaceAll` with the other list unchanged. The `songs` setter keeps today's `willSet` behavior: card cache
  first, then `objectWillChange.send()` on every set (as `@Published` did), then store.
- **Verify:** `B`, then `ARCH`. No test changes.

### Step 3: Scan and cache load through one writer

- Add `SongCatalogEdit` and `applyCatalogEdit(_:)` with the follow-up table. Implement `.rescan` and `.load`.
- `applyCatalogScanUpdate` calls `.rescan` and keeps only scan-only work. Cache load calls `.load` (B1).
- Tests: a cache load with an archived Vault snapshot already known gets the projected lists (B1); an unchanged rescan
  still refreshes intelligence and analytics without a browse recompute (existing `ArchiveRescanApplyTests` stay green).
- **Verify:** `B`, then `ARCH`.

### Step 4: Vault reprojection and New Song

- `.reproject` replaces `rebuildProjectVaultCatalog()` at its eight call sites. `.add` replaces the two writes in
  `createNewSong` (B4).
- Tests: a reprojection that removes an archived path from the baseline schedules an index persist (B2); New Song runs
  one browse recompute (count analytics history reads with analytics open, as `ArchiveAnalyticsTests` do).
- **Verify:** `B`, then `ARCH`.

### Step 5: Metadata edits and collaborator removal

- `.replace` replaces `replaceSong`. The metadata host's `applyReplacement` calls `.replace([song])`; collaborator
  removal calls `.replace(updatedSongs)` once (B3).
- Tests: removing a collaborator from three songs runs one browse recompute (B3); an equal replacement publishes
  nothing (B6, count `objectWillChange`); an edited selected song stays selected with its new value, and one that
  leaves the filtered list is deselected (requirement 5).
- **Verify:** `B`, then `ARCH`.

### Step 6: Root reset and per-song caches

- `clearRootBoundArchiveState` calls `.clear` instead of setting the two lists. The per-song cache follow-up (B5)
  replaces the hand-written clears of `mixdownBPMBySongID`, `mixdownKeyBySongID` and `cprPluginSummaryByCPRPath`
  that `.clear` now covers. Task cancellations and every non-catalog property stay.
- Tests: hiding archived projects drops their mixdown results (B5); a root reset leaves no per-song cache entry.
- **Verify:** `B`, then `ARCH`.

### Step 7: Tests seed through the writer; the old writers go

- Replace every test write of `.songs`/`.scannedSongs` (and `mutateCatalog { … }` around them) with
  `applyCatalogEdit(.load(songs))`. Do the same in `script/performance/archive-ui.swift`.
- Delete the transitional setters, `mutateCatalog(_:)` and its `ArchiveScanHost` requirement. `applyScanFailure` calls
  the browse recompute directly (it changes diagnostics, not the catalog).
- After this step, a write to `songs`, `scannedSongs` or `songCatalog` outside `ArchiveBrowserViewModel.swift` does
  not compile.
- A test whose expectation changes because it seeded a state production cannot reach (a visible list without a
  baseline) is fixed to seed a reachable state; record each such test as a revision.
- **Verify:** `B`, then `ARCH`. Plant a `songs = []` in another view-model extension file, see the build fail, remove it.

### Step 8: Docs, full gates, benchmark, live check

- `docs/architecture.md`: add "Archive song catalog" (the owner, the six edits, the follow-up table in short, why not
  an owner object). `docs/architecture-map.md`: the state-owner row for the catalog, gap 6 ("every writer keeps them
  consistent"), and the flow "Find a song" if it names the old writers. No AGENTS.md row: the compiler enforces the
  rule.
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - **Benchmark** on the 10k archive: build `script/performance/build-commit-binaries.sh catalog <final commit> launch`,
    run `script/performance/ab.sh launch <scratch>/ab 5 base catalog --scenarios launch,apply,search,browse`, and
    compare with `python3 -I script/performance/compare_runs.py <scratch>/ab`. Pass: the medians of
    `apply_catalog_update_board`, `apply_catalog_update_list`, launch, search and browse are within the run spread of
    the baseline, and `footprint_mib_after_launch` / `footprint_mib_end` are not higher. Then move `bakeoff-data/` and
    `BAKEOFF_NAME` to the Trash.
  - **Live check** with `verify-niko-music-hub`, in an isolated archive run:
    1. Relaunch: the board shows the fixture songs from the cache ("Loaded … from cache"), then the same songs after
       the rescan.
    2. Change a song's title or status in the song detail: the card shows it, and the song stays selected with the
       new value.
    3. New Song: the draft appears once and is selected.
    4. Assign one collaborator to two songs, remove the collaborator: both cards lose it.
    5. Settings > Archive: add a second root with one copied song folder, then remove it: its song leaves the board.
    6. "Show archived" with a Vault archive in the run (`features/project-vault.md`), or record why not.

## Completion criteria

- `applyCatalogEdit(_:)` is the only writer of the catalog, and the compiler enforces it.
- The seven writers use the six edits; `mutateCatalog`, `replaceSong`, `rebuildProjectVaultCatalog` and `songsByID`
  are gone.
- Every follow-up of a catalog change runs from one table; B1 to B6 are tested.
- Requirements 1 to 7 hold; existing tests pass, edited only where they wrote the catalog fields (each behavior-relevant
  edit recorded as a revision).
- The full gates, the benchmark and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the owner. This plan is deleted.

## Follow-ups (not part of this plan)

- **Root reset.** About 35 non-catalog statements still reset state by hand in `clearRootBoundArchiveState`. Grouping
  browse inputs and per-song analysis into owners would shorten it; finding #7 touches the same code.
- **Projection inputs.** If a second user of the projection appears, revisit Design B.
