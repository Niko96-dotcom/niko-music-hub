# Plan: Every Vault state change through one checked transition

**Status:** Approved by Niko on 2026-10-24: the whole plan, design A, fail-closed on an unlisted edge (decisions 1–3).
In progress — see Progress.  
**Date:** 2026-10-24  
**Source:** finding #13 of the 2026-10-22 architecture review ("Every Vault state change through the state machine",
rated Speculative, high risk). It closes gap 9 and open question 6 in [architecture-map.md](../architecture-map.md).  
**Scope:** how the transfer and restore engines change a record's state (`NikoMusicCore/Vault`:
`ProjectVaultStateMachine`, `LocalVaultTransferEngine`, `LocalVaultRestoreEngine`, `VaultRestoreRecord`, the restore
reconcile in `SQLiteVaultTransferStore`), their tests and docs. No change to a file operation, an admission, the
durability barrier, the manifest, the on-disk format, the SQLite schema or the UI.

This plan keeps two kinds of statement apart. **Current** describes the code at `c51e10f`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted.

## Progress

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | waiting for the UI lock (runs on a clone at `4302564`) | | |
| 1 Crash tests for every unguarded window, and a record of the real edges | done | this commit | 17 new tests pass on today's code; the Vault-related suites (filter `Vault\|Restore\|Recovery\|KeepLocal\|Friends\|ArchiveStorage\|Workflow\|Done`): 804 passed, 0 failed, no warning; plants A–J below each fail their test, source restored from a backup copy |
| 2 The transfer table lists exactly the real edges | not started | | |
| 3 Every transfer write goes through one checked function | not started | | |
| 4 Restore phases get their own checked table | not started | | |
| 5 Docs, full gates, live check | not started | | |

### Revision 1 (2026-10-24, step 1)

- **Re-check at `4302564`.** Every `file:line` above still matches: the engines, `VaultRestoreRecord` and
  `SQLiteVaultTransferStore` did not change since `c51e10f` (#8 changed `VaultAutomation.swift` and the runtime only).
- **Observed edges.** Temporary logging in both engines' `persist` and in the restore reconcile (not committed) logged
  the saved state before and after every save while every test matching `Vault|Restore|Recovery` and then
  `KeepLocal|Friends|ArchiveStorage|Workflow|Done|Archive` ran (1,760 passing test runs). Result: 27 transfer edges and
  7 restore edges, pinned in `VaultObservedEdges` (`Tests/NikoMusicCoreTests/VaultEdgeRecordingStore.swift`). Every one
  belongs to a path in the inventory above; none is new. Not observed (code paths no test reaches):
  `archivedOnlineOnly → archiveVerified`, `evictingProviderCache → archivedOnlineOnly`, the error and cancel routes into
  `recoveryRequired` at `:864, :891` (the same edges are observed through `:352`), `activeLocal` and `archiveEligible →
  failedRecoverable`, supersede from any state other than `failedRecoverable`, and the retry rewind to `activeLocal`,
  `archiveEligible` or `promotingArchiveGeneration`. Restore: superseded only from `copyingToActiveStaging`.
- **Crash seams.** `crashInjector` sits next to `faultInjector` on both engines (public like it; production passes
  none), with `VaultTransferCrashWindow` (11 windows) and `VaultRestoreCrashWindow` (3). `retryRecoverableTransfer`
  gets the `catch is VaultTransferInterruption` clause the other entry points already have, so a crash in the portable
  retry stands for process death instead of saving an error. No other production line changed.
- **Launch writes.** `:384` and `:419` use the existing phase fault points: they fire right after the rewind is saved,
  before the resumed phase's first side effect. `:282`, `:330` and `:352` have no side effect after their save in the
  launch pass, so a crash right after them leaves the journal of a finished pass: engine A's pass makes the write and
  engine B's two launches must change nothing. `:352` is the first launch in the removal crash tests.
- **Interrupted-removal recovery.** Only reads run between the move at `:553` and the save at `:529`, so "after the
  move" and "before `:529`" leave the same journal and files: one test with the Active folder present (moved) and one
  with it missing, plus one before the move.
- **Plants.** A: every crash window a no-op → the 13 window tests fail ("never reached"). B: the preservation path
  saved after the move → the before-the-move test fails. C, D: the launch and explicit retry rewinds not saved → their
  tests fail. E, F: survivor retirement and the legacy normalization not saved → their tests fail. G: `completedAt`
  saved before the open → the double-open test fails. H: the catalog flag saved before the catalog write → its test
  fails. I: `evictingProviderCache` saved before `removeItem` → the after-`removeItem` test fails. J: one edge removed
  from `VaultObservedEdges` → the recorder flags it.

## Decisions for Niko

1. **Design A or B** (see [Comparison](#comparison)). Recommended: A.
2. **What an unlisted edge does in a release build.** Recommended: fail closed — the engine throws before it saves or
   touches a file, and the transfer shows the failure text it shows today. The alternative (log and allow) keeps a
   transfer moving but makes the table advisory again.
3. **Stop after step 1?** Step 1 adds crash tests for the removal and recovery windows that have none today. It changes
   no production behavior and is worth doing on its own. Steps 2–4 then turn the table into the one owner. If the risk
   of steps 2–4 looks too high for the gain, approve step 1 only.

## Terms

- **Transfer state:** `VaultTransferState` (21 cases) on `VaultTransferRecord`, saved in `vault_transfers`.
- **Restore phase:** `VaultRestorePhase` on `VaultRestoreRecord`, saved in `vault_restores`. Restore does not use
  `VaultTransferState`.
- **Edge:** one from-state → to-state change that the code makes. A **rewind** is an edge back to an earlier state.
- **Fault point:** a test seam (`VaultTransferFaultPoint`, `VaultRestoreFaultPoint`) where a test throws
  `VaultTransferInterruption` to stand for process death; a second engine then runs launch recovery.
- **Write-ahead order:** the new state is saved before the file operation it describes, so launch recovery always
  knows what may have happened.

## Current architecture (observed at `c51e10f`)

### The state machine checks only the forward chain

`ProjectVaultStateMachine` (`ProjectVaultStateMachine.swift:140-201`) is pure: `applying(_:to:)` returns the next state
or throws. Its table (`:178-200`) holds the archive chain (activeLocal → … → promotingArchiveGeneration → archiveVerified),
the removal chain (archiveVerified → removingActiveCopy only with `VaultRemovalEvidence` → evictingProviderCache →
archivedLocal or archivedOnlineOnly) and a restore half (archivedLocal → materializingArchive → … → openingInCubase).

- Production callers: only `LocalVaultTransferEngine.swift:659` (removal) and the `advance` helper at `:1172`, which
  serves nine call sites (`:217, 680, 682, 703, 707, 712, 717, 792, 797`).
- Dead parts: `.fail(VaultFailure)`, `VaultFailure` and `VaultRecoveryDecision` have no production caller. The restore
  half is never used: restore has its own enum, which has `persistingActiveLocation` and no `readyLocal`.
- The removal evidence at `:660-664` always passes `manifestVerified: true, metadataPersisted: true`, so the gate checks
  only durability.

### Eleven transfer writes bypass it

| Line | Edge | Path |
| --- | --- | --- |
| 737 | promotingArchiveGeneration → archiveVerified | normal end (the edge is in the table, the check is skipped) |
| 646 | archiveVerified, archivedLocal, archivedOnlineOnly → archiveVerified | removal re-proof |
| 833, 850, 889 | removingActiveCopy → archiveVerified | admission denied, cancel or error before `removeItem` |
| 864, 352 | removingActiveCopy, evictingProviderCache → recoveryRequired | cancel at or after `removeItem`; launch normalization |
| 874 | any archive phase → failedRecoverable | cancel, also Done revoke |
| 891-893 | any → recoveryRequired or failedRecoverable | error |
| 282 | any recoverable state → superseded | launch, survivor retirement (read-compare at 279-281, not a CAS) |
| 330 | failedRecoverable → recoveryRequired | launch, legacy V1 records |
| 384, 419 | failedRecoverable → its origin, or copyingToArchiveStaging | launch auto-retry; explicit retry |
| 529 | recoveryRequired → archiveVerified | `recoverInterruptedRemoval` |

With the current table, `282, 330, 384, 419, 529, 646, 833, 850, 889` would be **rejected**; `352, 864, 874, 891-893`
pass only through the unused `.fail`. Seven of them are rewinds.

### Restore phases have no check at all

`LocalVaultRestoreEngine.advance` (`:835-838`) is `record.phase = phase` plus a save. The engine writes the forward
chain (`:430, 458, 462, 466, 479`), one rewind (`:449`, copying → materializing when staging is gone and the archive is
not local), and sets `completedAt` (`:484`) or `stoppedAt` (`:498`). The store's launch reconcile moves any incomplete
restore to superseded inside `BEGIN IMMEDIATE` (`SQLiteVaultTransferStore.swift:307`). There is no failed phase: a
failure sets `error` and `failureReason` and leaves the phase.

### Persistence and order

- Every save is one autocommit UPSERT of the state column plus the JSON record, with no expected-state check
  (`SQLiteVaultTransferStore.swift:51-56, 186-191`). The only state CAS is `compareAndSetProjectionSupplement` (`:155`).
- `proveRecoveryPersistence` (checkpoint plus file and directory sync) runs before supersede (`:272`), before entering
  removal (`:652`) and before `removeItem` (`:768`).
- Write-ahead order holds where tests check it: the 5 transfer fault points (`:684, 705, 709, 714, 719`) and the 6 restore
  fault points each fire after the phase is saved and before its side effect
  (`testEachFaultPointIsPersistedBeforeItsSideEffectAndLaunchRecoveryIsIdempotent`, `LocalVaultTransferEngineTests:1065`;
  `testVaultRestoreEachPersistedPhaseRecoversIdempotentlyAfterInterruption`, `LocalVaultRestoreEngineTests:1860`).
- **Windows without a crash test:** inside removingActiveCopy before and after `removeItem`; after eviction before the
  save at `:797`; between a finished copy and its save (`:969`); between the rename and `:736`; between `:736` and `:740`;
  between `:650` and `:667`; around the move at `:553` and before `:529` in `recoverInterruptedRemoval`; the portable-retry
  move at `:466`; right after each launch write (`282, 330, 352, 384, 419`); on restore, the rename before `:466`, the
  catalog write before `:477`, and the open before `:486`.
- Known non-atomic pair: the restore opens the project (`:483`) and then saves `completedAt` (`:486`). A crash between
  them opens the project a second time at the next launch (inferred from the code; step 1 pins it with a test).

## Design A — one edge table per record type, one checked write per engine (chosen)

- **Transfer table = the real edges.** `ProjectVaultStateMachine` keeps its shape (`applying(_:to:)`,
  `allowedDestinations`). Its table gains the edges the engine really makes, rewinds included, each with a comment that
  names the path (cancel before removal, launch normalization, retry, recovery of an interrupted removal, supersede). The
  removal edge keeps its evidence check. The unused restore half and the dead `.fail` / `VaultFailure` /
  `VaultRecoveryDecision` go (the deletion test: nothing in production needs them).
- **One write per engine.** Every transfer state change goes through the engine's existing `advance` helper (renamed
  to say it checks and saves). A source test fails when any other line in `Sources/` assigns a transfer `state` or a
  restore `phase`.
- **Restore table.** `VaultRestorePhase` gets a small table of its own: the forward chain, the rewind at `:449`, and
  any incomplete phase → superseded. Both `LocalVaultRestoreEngine.advance` and the store's reconcile check it.
- **Edges come from observation, not from memory.** Step 1 records every edge the existing transfer and restore suites
  make (a recording store wrapper in tests). Step 2 has a test that the table contains every recorded edge, so an edge
  the inventory missed fails a test, not a person's transfer.

## Design B — a journal type owns state and saving (not chosen)

A `VaultTransferJournal` (and a restore journal) would own the record's state field, the transition check, the save,
an expected-state compare-and-set in the store (`UPDATE … WHERE state = ?`), and the ordering with
`proveRecoveryPersistence`. The engines would send events and could not write state at all (compiler-enforced instead of
a source test). It would also replace the read-compare at `:279-281` with a real CAS.

- **Why not now:** it moves `persist` out of both engines, changes the store protocol and the fakes in five test files,
  and restructures the code that removes Active project folders, all in one change. A is a strict subset: after A, every
  write already passes one function, so B becomes a contained follow-up.

## Comparison

| | A: edge tables + one checked write | B: journal owns state and saving |
| --- | --- | --- |
| Depth | The table states every legal change; one function per engine | More: state, check, save and CAS behind one interface |
| Enforcement | Source test for direct writes; test that the table covers observed edges | Compiler (no setter outside the journal); CAS at the store |
| Behavior | Unchanged on every path the tests know; an unlisted edge fails closed | The same, plus a stale writer is refused |
| Risk | Medium: one call per write site changes, no file-operation change | High: save path and store protocol change in the removal code |

**Decision: A**, after step 1's crash tests exist.

## Behavior and compatibility requirements

1. **Same behavior.** Every existing Vault test passes unchanged. No file operation, admission, barrier, fault-point
   order, retry rule, error text or UI changes. The schema and the saved JSON stay the same.
2. **Write-ahead order kept.** The new state is saved before its side effect; the new crash tests prove it for each
   window listed above.
3. **One writer per record type.** Only the transfer engine's checked function assigns `state`; only the restore
   engine's checked function and the store's reconcile assign `phase`, both through the restore table.
4. **Unlisted edge (decision 2).** The engine throws `VaultTransitionError` before it saves or touches a file. The record
   keeps its last saved state.
5. **The removal gate does not get weaker.** The evidence check stays on the removal edge. (Its constant
   `manifestVerified` / `metadataPersisted` inputs are a follow-up, not changed here.)

## Steps

Each step is one commit, green under focused tests; step 5 runs the full gates from Terminal.app and the live check.

### Step 0: Baseline

Full gates on the starting commit.

### Step 1: Crash tests for every unguarded window, and a record of the real edges

- Add internal fault points for each window in [Persistence and order](#persistence-and-order) and one crash-then-launch
  test per window: engine A stops at the point, engine B runs launch recovery twice, and the test checks state, the
  Active folder, the generation and that nothing is replayed. The tests pin today's results, including the second open
  after a crash between `:483` and `:486`.
- Add a test-only recording store that logs each saved (from, to) pair, and run the transfer and restore scenarios
  through it. The output is the list of observed edges.
- **Verify:** all new tests pass on today's code; plant: move one save after its side effect → the matching test fails.

### Step 2: The transfer table lists exactly the real edges

- Extend the table with the observed edges, each with its path comment; remove the restore half and the dead `.fail`
  family. A test asserts that the table contains every edge from step 1 and rejects a sample of illegal edges.
- **Verify:** `ProjectVaultStateMachineTests` plus the new coverage test; plant: drop one rewind edge → the coverage test
  fails.

### Step 3: Every transfer write goes through one checked function

- Replace the eleven direct writes with the checked function. Add the source test for direct `state` assignments.
- **Verify:** every transfer, durability and recovery suite unchanged and green; plant: a direct
  `record.state = .archiveVerified` → the source test fails; an illegal edge → the engine throws before any file
  operation (test with a recording file manager).

### Step 4: Restore phases get their own checked table

- Add the restore table; `advance` and the store's reconcile use it; extend the source test to `phase`.
- **Verify:** restore, linked-restore and reconcile suites unchanged and green; plant as in step 3.

### Step 5: Docs, full gates, live check

- `docs/architecture.md`: a "Vault state changes" section (the two tables, the one writer, write-ahead order, the crash
  tests). `docs/architecture-map.md`: gap 9 and open question 6 closed; the state-owner row names the table.
  `docs/vault-durability.md`: the test list.
- Full gates; link check; delete this plan.
- **Live check** (verify skill, scratch Vault): Create Backup Copy; Archive Copy; Restore & Open; quit the app during a
  backup copy and relaunch — recovery finishes or reports as today. Removal stays blocked while a DAW runs; report it as
  blocked unless Niko closes the DAWs.

## Completion criteria

- One table per record type lists every edge the code makes; a test fails when the code makes an edge the table lacks.
- Only one function per engine (and the restore reconcile) writes state; a source test enforces it.
- Every window listed above has a crash-then-launch test.
- Requirements 1–5 hold; the full gates and the live check are green on the final commit; docs updated; plan deleted.

## Follow-ups (not part of this plan)

- **Design B:** expected-state compare-and-set in the store, and a journal type that owns the save.
- **Real removal evidence:** compute `manifestVerified` and `metadataPersisted` instead of passing `true`.
- **Restore double open after a crash** between the open and `completedAt` (visible to a person; needs Niko).
