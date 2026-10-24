# Plan: Remove the "Archive automatically" switch and its unused machinery

**Status:** Approved by Niko on 2026-10-24, including decision 1 (the login-item row goes) and the new error texts.
In progress — see Progress.  
**Date:** 2026-10-24  
**Source:** finding #8 of the 2026-10-22 architecture review; gap 8, the "Documents that disagree" bullet on
background scheduling, and open question 5 in [architecture-map.md](../architecture-map.md).  
**Scope:** the background-archiving setting and everything only it uses: `VaultSettings` fields, Settings → Vault rows,
the Vault login-item policy, the unused branches of `NikoMusicCore/Vault/VaultAutomation.swift`, the rollout gates,
settings repair, the recovery bundle, diagnostics, docs and tests. The automatic **Done copy** stays exactly as it is.
No change to transfers, restores, removal, Keep Local, Emergency Stop, the probes or the on-disk format.

**Current** describes the code at `c51e10f`. **Planned** describes the target. When the plan is done, the lasting part
moves to [architecture.md](../architecture.md), and this file and the decision memo are deleted.

## Progress

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | taken from the coordinator | | `c51e10f`: 2,900 passed, 0 failed, 8 skipped; Swift Testing 86 passed |
| 1 A true message when a Done archive is refused | done | `8096db7` | strict build, 0 warnings; Vault suites 242 run, 0 failures; plant (order swap, two throw sites made constant) → exactly the 3 new tests fail |
| 2 The settings and their readers go | done | this commit | strict build, 0 warnings; settings, repair, bundle, Vault, Keep Local and source suites 395 run, 0 failures; plant (decoder rejects unknown keys, a login row in the Vault pane, repair lists "automatic archiving") → the 1.8.1 payload test, the 1.8.1 bundle test, the Vault-pane guard and both repair tests fail; General subtitle (revision 6a): plant (subtitle back) → the Vault-pane guard fails |
| 3 The automation code keeps only what the Done copy uses | not started | | |
| 4 Docs, full gates, live check | not started | | |

## Revisions

Facts re-checked against `c51e10f` (origin/main had not moved) on 2026-10-24. Every `file:line` in this plan
matches, except:

1. **`.invalidPolicy` stays.** It is not produced only by the dead paths: `VaultArchiveWriteAdmissionEvaluator`
   returns it for an out-of-range reserve, `LiveProjectVaultRuntime+Admission.swift:142` throws it when the settings
   cannot be read during a write admission, and `LocalVaultTransferEngine.swift:1191` maps it to
   `.insufficientSpace`. Design A removes the evaluator's own `.invalidPolicy` check (`VaultAutomation.swift:158-162`),
   not the case. Its text "Check the Project Vault free-space and inactivity settings." still names the removed
   inactivity setting; the plan does not list a new text, so it stays as it is (follow-up).
2. **`activeAvailableCapacityBytes` stays in `ProjectVaultCapacitySnapshot`.** After step 3 nothing reads it, but the
   probe reads the Active volume as part of one throwing snapshot, so removing the read would let a Done copy start
   when the Active volume cannot be read. That is a behavior change outside this plan (follow-up).
3. **Step 1 runtime tests.** `configuration()` refuses a Vault that is off or has a missing folder with
   `.unavailable` before any of the three throw sites run, so the `.disabled` (Vault off) and `.unavailable`
   reasons of `userInitiatedRefusal` are covered by policy tests; the runtime tests cover the reasons the runtime
   can reach (disabled rollout, Emergency Stop, removal not chosen at capture and at removal, backup not confirmed).
4. **`VaultLaunchAtLoginTests` goes with the policy it tested.** Its source checks that still apply moved to
   `SettingsLiquidSourceTests.testVaultSettingsOfferNoBackgroundArchivingAndNoLoginItem` (the Vault pane shows no
   automation or login row; General's switch is the one login writer). The deleted test also pinned the General
   subtitle "Lets Project Vault archive while you’re away", which promises background archiving as well; the plan
   did not list it (see 6).
5. **`SettingsStoreTests` loses three payloads** (`automaticArchiving`, `inactivityDays`, `launchAtLogin` set to
   null): those keys are now ignored, so such a payload loads, which is requirement 2.
6. **Two more texts, approved by Niko on 2026-10-24 during implementation.** (a) Step 2: Settings → General →
   "Open at login" loses the subtitle "Lets Project Vault archive while you’re away"; the row shows only "Open at
   login". Guarded by `testVaultSettingsOfferNoBackgroundArchivingAndNoLoginItem`. (b) Step 3: the `.invalidPolicy`
   text "Check the Project Vault free-space and inactivity settings." becomes "Check the Project Vault free-space
   settings."

## Decisions for Niko

1. **The Vault login-item row goes too** (recommended). Settings → Vault shows "Login item: On/Off" with an "Open Login
   Setting" button (`ProjectVaultSettingsView.swift:400-423`). Its only purpose was to warn that background copies need
   the app open at login. Open at login stays in Settings → General.
2. **The new error texts** in step 1 (the exact strings are in that step).

## What a person sees after this plan

- Settings → Vault no longer shows "Archive automatically", "After *n* days untouched", "Or when less than *n* GiB is
  free", the login-item row and its warning. Every other row stays.
- Marking a song Done still makes a verified Vault copy, as today.
- A refused Done archive names the real reason (Vault off, folders missing, Emergency Stop, Keep Local review, removal
  not chosen, backup not confirmed) instead of "Automatic archiving is turned off."
- Diagnostics exports lose four lines (`automatic_archiving`, `automation_permitted`, `inactivity_days`,
  `minimum_free_space_gib`).

## Current architecture (observed at `c51e10f`)

- **The switch.** `VaultSettings.automaticArchiving`, `inactivityDays`, `minimumFreeSpaceGiB` and `launchAtLogin`
  (`AppSettings.swift:91-98`, defaults false/30/120/true at `:131-136`, coding at `:195-251`). Settings rows at
  `ProjectVaultSettingsView.swift:48-73`; login-item row at `:93, 400-423`.
- **No background trigger exists.** No code builds a `.policy` candidate (`VaultAutomation.swift:30-33`); git history
  shows none ever did. The inactivity and low-space branches (`:171-183`) are unreachable.
- **The Done copy** goes through `LiveProjectVaultRuntime.runAutomaticArchive` (`+Archive.swift:455-520`). It builds the
  policy with the switch hard-coded on (`:474`), passes the days and GiB only to a validity check that the UI ranges
  always pass (`VaultAutomation.swift:158-161`), and sets `isKeepLocal: false` (`:493`) because Keep Local was checked
  before (`:402-405`). `VaultAutomationScheduler` defaults to `removesActiveCopy: true` (`:580`); the Done caller
  overrides it (`:487`).
- **Readers of the switch:** diagnostics (`ProjectVaultDiagnosticsExporter.swift:18, 20, 27, 28`), the login warning
  (`LaunchAtLoginControlling.swift:46-85`; computed and discarded at launch by `VaultLaunchAtLoginReconciler`,
  `AppComposition.swift:49-58`), settings repair (`SettingsRepair.swift:177, 191-198, 231-242, 303-315`), the recovery
  bundle (`ProjectVaultRecoveryBundle.swift:24, 389-391`), `ProjectVaultRolloutPolicy.permitsAutomaticArchiving`
  (diagnostics only) and `permitsActiveCopyRemoval` (no caller), and a DEBUG command
  (`BookmarkRelaunchProofCommands.swift:33`).
- **The wrong message.** `ProjectVaultRuntimeError.automaticArchivingDisabled` ("Automatic archiving is turned off.") is
  thrown when `permitsUserInitiatedArchiving` or `permitsUserInitiatedRemoval` refuses a Done archive
  (`+Archive.swift:134, 399`; `+Admission.swift:369`). The causes are other settings.

## Design A — delete the dead inputs, keep the scheduler as the Done runner (chosen)

- `VaultAutomationPolicy` keeps `isVaultEnabled`, `transferFreeSpaceReserveGiB` and `writeQuietPeriod`.
- `VaultAutomationCandidate` loses `trigger`, `lastActivityAt`, `availableCapacityBytes` and `isKeepLocal` (constant in
  production). `VaultAutomationEligibilityReason` goes; eligibility is eligible or postponed.
- `VaultAutomationPostponement` loses `automaticArchivingDisabled`, `invalidPolicy`, `unknownLastActivity`,
  `notOldEnoughAndNoDiskPressure` and `keepLocal` (only the dead paths produce them). Every live case stays.
- `VaultAutomationScheduler` loses `failureSink` (never passed) and its default for `removesActiveCopy`: every caller
  must say whether it removes. Its doc comment describes the Done run.
- `ProjectVaultRolloutPolicy.permitsAutomaticArchiving` and `permitsActiveCopyRemoval` go.

## Design B — fold the scheduler into the runtime (not chosen)

Delete `VaultAutomationScheduler`, the policy, candidate and evaluator, and write the Done run (capacity check, probe,
copy, re-probe, optional removal) directly in `runAutomaticArchive`. It deletes more, but it moves the probe-copy-reprobe
order, which protects the Active copy, from NikoMusicCore into AppCore, and its tests
(`testActivityBecomingBusyAfterCopyRetainsActiveCopy` and the probe tests) would need the heavier runtime fixture. A
stays a small deletion with the same seams; B can follow later if the scheduler still looks shallow.

## Behavior and compatibility requirements

1. **The Done copy is unchanged**: same gates, same probes, same copy-only default, same removal only with a bound
   authorization. Every Done, queue and runtime test passes unchanged, except the tests this plan names.
2. **Old settings load.** A stored payload with the four removed keys decodes without a repair and keeps every other
   value (a test with a 1.8.1 payload). An older app that reads new settings gets its defaults (switch off), which is
   safe.
3. **Old recovery bundles import**, and a new bundle imported by 1.8.1 is safe (defaults).
4. **Repair stays as strict**: a damaged Vault payload still pauses removal and sets Emergency Stop; it no longer lists
   "automatic archiving" among the reset items.
5. **No guard gets weaker.** Each removed check is unreachable in production today (the inactivity and low-space
   branches, the always-true flag, the always-false Keep Local input, the always-passing validity check). Keep Local is
   still checked at capture and in `validateAutomaticArchivingEligibility`; the scheduler's removal default becomes an
   explicit argument.
6. **Docs match the app**: no doc or UI text promises background archiving.

## Steps

Each step is one commit, green under focused tests and the strict build; step 4 runs the full gates from Terminal.app
and the live check.

### Step 0: Baseline

Full gates on the starting commit.

### Step 1: A true message when a Done archive is refused

- `ProjectVaultRolloutPolicy.userInitiatedRefusal(_ settings:, removing: Bool) -> ProjectVaultRuntimeError?` returns
  the first failing reason in this order: Emergency Stop (`.emergencyStop`), Vault off or a stored disabled rollout
  (`.disabled`, "Project Vault is turned off."), a missing folder (`.unavailable`); with `removing`, also a pending Keep
  Local review (`.keepLocalReviewRequired`), removal not chosen (new `.removalNotChosen`), backup not confirmed
  (`.independentBackupRequired`). `permitsUserInitiatedArchiving` and `permitsUserInitiatedRemoval` become
  `userInitiatedRefusal(…) == nil`, so the gates cannot drift from the messages.
- New text for `.removalNotChosen`: "After archiving is set to keep the Active copy, so it was not removed." (True at
  all three sites: at `+Archive.swift:134` nothing was copied yet; at the other two a verified copy may exist.) The
  three throw sites throw the returned reason; `.automaticArchivingDisabled` goes.
- **Verify:** a runtime test per reason; `LiveProjectVaultRuntimeTests:4504` changes from `.automaticArchivingDisabled`
  to the real reason (recorded as a revision); plant: swap two reasons in the order → the order test fails.

### Step 2: The settings and their readers go

- Remove `automaticArchiving`, `inactivityDays`, `minimumFreeSpaceGiB` and the Vault `launchAtLogin` from
  `VaultSettings` (properties, init, coding, defaults). Remove the three Settings rows and, per decision 1, the
  login-item row with its callback; remove `VaultLaunchAtLoginPolicy`, `VaultLaunchAtLoginDecision`,
  `VaultLaunchAtLoginReconciler` and its call in `AppComposition` (the `SMAppServiceLaunchAtLoginController` for General
  stays). Update settings repair (salvage table, fields, the reset list), the recovery bundle (import and
  `scopeNote`), diagnostics, the DEBUG command and every test fixture that sets the fields.
- **Verify:** `VaultSettingsTests`, `SettingsStoreTests`, `SettingsRepairTests`, `ProjectVaultRecoveryBundleTests`, the
  Vault settings and polish tests; new: a 1.8.1 payload with the four keys decodes with no repair and keeps its other
  values; plant: make the decoder reject unknown keys → the new test fails.

### Step 3: The automation code keeps only what the Done copy uses

- Apply Design A to `VaultAutomation.swift` and the runtime's `runAutomaticArchive`. Delete the policy-only tests
  (`VaultAutomationTests:9, 37`); move the scheduler tests that used `.policy` candidates (`:92, 122, 142, 180`) to Done
  candidates with an explicit `removesActiveCopy`, keeping their assertions.
- **Verify:** `VaultAutomationTests`, `LiveProjectVaultRuntimeTests`, the archive Done and queue suites; plant: give
  the Done caller `removesActiveCopy: true` → a copy-only Done test fails.

### Step 4: Docs, full gates, live check

- Docs: `docs/vault-durability.md:21`, `docs/ableton-and-project-restore.md:58, 72`, `docs/vault-recovery.md:18, 71`;
  `docs/architecture-map.md` closes gap 8, the disagreement bullet and open question 5; `docs/architecture.md` states in
  one line that the only automatic archiving is the Done copy. `CHANGELOG.md`: an `## Unreleased` entry. The local
  verify skill's `features/settings.md` and `project-vault.md` if they mention the switch.
- Full gates; link check; delete this plan and the decision memo.
- **Live check** (verify skill, scratch Vault): Settings → Vault shows no automation rows and no login-item row; Done on
  a fixture song still makes a verified copy (copy-only); with "After archiving" on keep copy, a removal request shows
  the new `.removalNotChosen` text; relaunch keeps every other Vault setting; a diagnostics export has no automation
  lines.

## Completion criteria

- No UI text, doc or setting promises background archiving; the Done copy works as before.
- The removed fields, rows, policies and branches are gone; old settings and bundles still load.
- A refused Done archive names its real cause.
- The full gates and the live check are green on the final commit; this plan and the memo are deleted.

## Follow-ups (not part of this plan)

- Design B (fold the scheduler into the runtime), if it still looks shallow after step 3.
- The `privateBeta` rollout label "Private beta (automatic copies only)" (`AppSettings.swift:58`) is not shown; remove it
  with the rollout stage cleanup, if that is ever planned.
