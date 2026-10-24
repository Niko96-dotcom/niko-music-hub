# Plan: An interrupted removal goes to review, never to `superseded`

**Status:** Approved by Niko on 2026-10-24: "a transfer in a removal phase that survivor retirement would mark
superseded goes to recoveryRequired instead." In progress.  
**Date:** 2026-10-24  
**Source:** the open item that lane D (finding #13, `c94311b..6cc8545`) left in
[architecture.md § Vault state changes](../architecture.md#vault-state-changes).  
**Scope:** launch survivor retirement in `LocalVaultTransferEngine.recoverAtLaunchReport()`, two rows of the transfer
table in `ProjectVaultStateMachine`, their tests and docs. No change to a file operation, an admission, the durability
barrier, the manifest, the journal format or the UI.

When the work is done, the lasting part moves to [architecture.md](../architecture.md) and this file is deleted.

## Current (at `6cc8545`)

- `recoverAtLaunchReport()` (`LocalVaultTransferEngine.swift:290-328`): for each project with a verified generation,
  after the fresh durability re-proof, the binding check and the journal proof, every causally older incomplete record
  of the project is saved `superseded` (`supersededBy` = the survivor). That includes `removingActiveCopy`,
  `evictingProviderCache` and a legacy `failedRecoverable` whose `error.origin` is one of the two. Such a record leaves
  the person's view: the snapshot skips `superseded` records, so the Active folder that the removal may have
  removed in part has no review handle.
- The later launch path (`:347-397`) normalizes a removal phase or a legacy failed removal to `recoveryRequired`, but
  only for the newest record of each project (`VaultTransferRecoveryPolicy.candidates`), and retirement runs first.
- The table allows `removingActiveCopy → superseded` and `evictingProviderCache → superseded`
  (`ProjectVaultStateMachine.swift:140-141`). No test made either edge (`VaultObservedEdges`).

## Planned

1. **One rule for an interrupted removal at launch.** A small engine function names the removal origin of a record
   (its removal state, or the removal origin of a legacy failure) and saves it `recoveryRequired` through
   `checkAndSave`, with the existing launch message for that case, `nextRetryAt` cleared, `supersededBy` nil, and the
   manifest, durability and paths kept. No file is touched. Both the retirement loop and the later launch path call
   it, so the two cannot drift.
2. **Retirement decides it in place.** In the retirement loop, a record with a removal origin goes to review instead
   of `superseded`; every other older record retires as today. The decision does not wait for the later path, which
   sees only the newest record of a project. Records handed to review leave the later loop's input and join the
   results, so nothing saves them twice.
3. **The table fails closed.** `.superseded` leaves the `removingActiveCopy` and `evictingProviderCache` rows.
   `failedRecoverable → superseded` stays, because a failure in an archive phase still retires; the origin check for a
   legacy failed removal lives in the engine.
4. **Reading of "a transfer in a removal phase":** the two removal states, plus a legacy `failedRecoverable` record
   whose `error.origin` is a removal state (launch already treats that record as an interrupted removal).

## Tests (written first; each fails on `6cc8545`)

In `VaultCrashWindowTests` (launch writes, edge recorder on):

- A verified archive saved in `removingActiveCopy`, then in `evictingProviderCache`, then as a legacy
  `failedRecoverable` removal, each with a newer verified generation: launch ends `recoveryRequired` with the removal
  origin and no `supersededBy`; a second launch changes nothing; no file operation; `recoverInterruptedRemoval`
  then returns `archiveVerified`.
- In the same project, an archive-phase failure older than the survivor still retires to `superseded`.
- An older removal record that is not the newest incomplete record of its project (a newer failure with a spent retry
  budget stays) still ends `recoveryRequired`.

In `ProjectVaultStateMachineTests`: the frozen graph without the two edges, and both edges in the rejected list.

## Checks

- Focused: `swift test --filter 'VaultCrashWindowTests|ProjectVaultStateMachineTests|VaultStateWriterSourceTests'`,
  then the Vault-related suites.
- Full gates from Terminal.app: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh`.
- Live check: an isolated run with a seeded scratch journal (a removal-phase record plus a newer verified generation of
  a scratch fixture project); at launch the project shows the review state, and Recover verifies and restores it.
