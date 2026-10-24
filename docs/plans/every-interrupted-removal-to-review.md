# Plan: Every interrupted removal goes to review at launch

**Status:** Approved by Niko on 2026-10-24: "at launch, every interrupted removal of a project goes to
recoveryRequired, also when it is not the newest record and also when the survivor checks fail." In progress.  
**Date:** 2026-10-24  
**Source:** the gap lane E (`3c5ef22`, `086581d`) reported after it handed an interrupted removal to review when a
newer verified generation exists.  
**Scope:** `LocalVaultTransferEngine.recoverAtLaunchReport()`, its tests and the Vault docs. No change to the state
table, a file operation, an admission, the durability barrier, the manifest, the journal format or the UI.

When the work is done, the lasting part is in [architecture.md](../architecture.md) and this file is deleted.

## Current (at `086581d`)

- `interruptedRemovalOrigin(of:)` names a record's removal phase (`removingActiveCopy`, `evictingProviderCache`, or the
  origin of a legacy `failedRecoverable` saved in one); `handInterruptedRemovalToReview(_:origin:)` saves it
  `recoveryRequired` through `checkAndSave`.
- Two call sites decide an interrupted removal at launch: the survivor-retirement loop, only after the survivor's fresh
  durability check, binding check and `proveRecoveryPersistence()` pass; and the later pass over
  `VaultTransferRecoveryPolicy.candidates(from:)`, which sees only the newest incomplete record of each project.
- So an older interrupted removal keeps its removal state when (a) a newer verified survivor exists but one of its
  checks fails, or (b) no verified survivor exists and a newer incomplete record of the project exists. With an
  unreadable journal row (`holdsByteWork`), retirement does not run, so only case (b) applies, for every project.
- A failed hand-off save in the retirement loop leaves the record in `records`, so the later pass tries it again in the
  same launch.

## Planned

1. **One pass, first.** Right after the journal read, with no await before it, every readable incomplete record with
   a removal origin goes through `handInterruptedRemovalToReview` and leaves `records`, whatever else the project
   holds and whether or not a journal row is unreadable. The two later call sites go.
2. **A failed save keeps the record as it was.** The record is returned unchanged and is still removed from
   `records`, so launch never resumes, retries or retires it (a legacy `failedRecoverable` keeps its
   `failedRecoverable → superseded` edge for archive-phase failures, so this matters). The next launch tries again.
3. **Retirement and the newest pass stay as they are** for every other record. Retirement may now skip a survivor's
   verification when the only older records were removals, because nothing is left for it to retire.
4. **Legacy metadata migration:** `needsLegacyMetadataMigration` is true only for a record that resumes at
   `awaitingProviderDurability`, and `recoverInterruptedRemoval` verifies the generation, not the staging folder that
   migration rewrites. So no interrupted removal ever reaches migration, and the hand-off can run first.

## Tests (written first; each fails on `086581d`)

In `VaultCrashWindowTests`:

- An older removal, a newer verified survivor, a newer failure with a spent retry budget, and a survivor check that
  fails (persisted durability that the fresh claim does not match; changed generation bytes; a failed journal proof):
  the removal ends `recoveryRequired`, the newer failure stays, no file is touched.
- An older removal, no verified survivor, and a newer failure with a spent retry budget: the removal ends
  `recoveryRequired`; the newer failure stays.
- The same with an unreadable journal row: the row stays unread and unchanged.
- A hand-off save that throws (removal state and legacy failure, with a survivor and an older archive failure): the
  removal keeps its saved state, is returned unchanged, is not superseded and nothing is resumed; the archive failure
  retires; the next launch hands the removal to review.

Lane E's tests in `VaultCrashWindowTests` and `LocalVaultTransferEngineTests` stay unchanged and pass. Plant: skip the
new pass and show which tests fail; restore the source byte for byte.

## Checks

- Focused: `swift test --filter 'VaultCrashWindowTests|LocalVaultTransferEngineTests|LocalVaultDurabilityFaultTests|ProjectVaultStateMachineTests|VaultStateWriterSourceTests'`.
- Full gates from Terminal.app: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh`.
- Live check: an isolated run with a scratch fixture archive; an older removal-phase row plus a newer incomplete row of
  the same project seeded with the app stopped; at launch the project shows "Needs attention" and "Recover Verified
  Project" works.
