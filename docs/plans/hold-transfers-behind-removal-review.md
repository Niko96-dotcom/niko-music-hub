# Plan: Other transfers of a project wait while its interrupted removal waits for review

**Status:** Approved by Niko on 2026-10-24: "at launch, a newer incomplete transfer of a project that has an
interrupted removal is not resumed or retried; it waits until the person recovers the interrupted removal." In
progress.  
**Date:** 2026-10-24  
**Source:** the gap lane F (`238426a`) reported after it handed every interrupted removal to review at launch.  
**Scope:** `LocalVaultTransferEngine.recoverAtLaunchReport()`, `LiveProjectVaultRuntime.nextAutomaticRecoveryDate()`,
their tests and the Vault docs. No change to the state table, a file operation, an admission, the durability barrier,
the manifest, the journal format, the person's Retry, a new copy, the Done retry or the UI.

When the work is done, the lasting part is in [architecture.md](../architecture.md) and this file is deleted.

## Current (at `238426a`)

- The first pass of `recoverAtLaunchReport()` hands every readable interrupted removal to `recoveryRequired` and
  removes it from `records`. Survivor retirement and the newest-record pass then run as before.
- So the newest other incomplete record of that project is still resumed (`execute`), retried (the
  `failedRecoverable → origin` rewind) or migrated (`migrateLegacyMetadataFiles`) in the same launch. When the removal
  was the newest record, the next older incomplete record becomes the newest and is retried. Both copy or promote
  bytes of an Active folder the removal may have left incomplete, and the result becomes the generation a restore
  uses.
- `nextAutomaticRecoveryDate()` reads only `recoverableRecords()` (no `recoveryRequired` row), so such a record keeps
  its due date. Once the launch pass holds it, the recovery timer would fire every 30 s for nothing.

## Planned

1. **One named rule in the engine**, next to `interruptedRemovalOrigin(of:)`: `projectsAwaitingRemovalReview(in:)`
   returns the projects that have a readable record with an interrupted-removal origin (handed to review in this
   pass, or kept as saved because the hand-off save threw) or a record already in `recoveryRequired` whose
   `error.origin` is `removingActiveCopy` or `evictingProviderCache`. Public and static, so the runtime uses the same
   rule.
2. **Launch:** the held set is computed from the journal read at the start (`allRecords`, readable rows only). In the
   newest-record pass, a record of a held project is returned unchanged before migration, the retry rewind or
   `execute`. Survivor retirement still runs: it touches no file and may mark an older record `superseded`.
3. **Older records too:** the newest-record pass reads only the newest record of each project, so one check there
   holds every other incomplete record of the project, newer or older than the removal. My reading: an older
   incomplete record copies the same Active folder, so it waits as well.
4. **Timer:** `nextAutomaticRecoveryDate()` drops the candidates of held projects, using the same rule over
   `allTransferRecordsReport().records` (readable rows; an unreadable row does not make the timer read fail).
5. **After recovery:** `recoverInterruptedRemoval` saves the removal `archiveVerified`, so the rule no longer names
   the project; the next launch or timer run resumes the record as it would today. No new trigger.
6. **Unreadable rows** keep `holdsByteWork` as it is.

## Tests (written first; each fails on `238426a`)

In `VaultCrashWindowTests` (both removal phases and both legacy failures where it applies):

- An interrupted removal plus a newer retryable `failedRecoverable`: the newer record keeps its state, its staging
  bytes do not change, it is in the results, and no file operation runs.
- An interrupted removal plus a newer `copyingToArchiveStaging` record: not resumed.
- A removal already in `recoveryRequired` from an earlier launch plus a retryable record: held.
- A hand-off save that throws: the project is still held in that launch.
- An older retryable record of the same project (the removal is the newest): held.
- Another project in the same journal: its retryable record is retried as usual.
- After `recoverInterruptedRemoval`, the next launch resumes the held record.

In `LiveProjectVaultRuntimeTests`: the due date skips a held project (removal in a removal phase or already in
review), keeps another project's due date, a recovery run changes nothing for the held record, and the due date
comes back once the removal is `archiveVerified`.

Lane E and lane F tests stay unchanged and pass. Plant: disable the hold, list which tests fail, restore the source
byte for byte.

## Checks

- Focused: `swift test --filter 'VaultCrashWindowTests|LocalVaultTransferEngineTests|LocalVaultDurabilityFaultTests|ProjectVaultStateMachineTests|VaultStateWriterSourceTests|LiveProjectVaultRuntimeTests'`.
- Full gates from Terminal.app: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh`.
- Live check (verify skill, scratch run): an older removal-phase row plus a newer retryable row of the same project,
  seeded with the app stopped. At launch the removal goes to review, the newer row is not retried (no new staging
  bytes), the card shows "Needs attention"; no repeated recovery runs for about two minutes; then "Recover Verified
  Project" and a relaunch.
