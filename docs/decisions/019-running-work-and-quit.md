# Decision: One registry of running work, and a quit contract that reads it

**Status:** Accepted — process-group backstop and quit prompt implemented; recorder takes and helper installs not yet registered  
**Date:** 2026-09-27  
**Deciders:** Niko Music Hub owner + implementation  
**Scope:** App termination, helper processes, `ShellJobStatusCenter`

## Context

Quit consults one closure (the Project Vault queue count) and cancels nothing on
confirm. Downloads, stems, the converter and the archive scan / Vault queue are
already visible to `ShellJobStatusCenter`; recorder takes and helper installs are
not.

`FoundationExternalProcessRunner` starts every helper (yt-dlp, ffmpeg,
demucs-mlx, the helper installer, analysis tools) as the leader of its own
process group, so cancellation and timeouts reach the helper's descendants too.
The same isolation means a helper that is still running when the app quits is not
signalled by anyone: it keeps running, orphaned, after Music Hub is gone.

The center's `cancel` is fire-and-forget and some cancel closures hop to the main
actor, so a blocking wait inside `applicationShouldTerminate` would never see them
finish.

## Decision

1. `ShellJobStatusCenter` is the one registry of work that must not be cut off
   silently. Recorder takes (cancel = finalize the file) and helper installs
   register there too. A `listed` flag on `ShellJobStatus` separates "shown in the
   jobs strip" from "counts at quit".
2. **Quit prompt (implemented).** `HubTerminationCoordinator` (AppCore) reads
   `ShellJobStatusCenter.quitBlockingWork`: every unfinished `JobRunner` job
   (downloads, stems) plus the extra sources whose `ShellJobStatus.blocksQuit`
   is set (the converter and the Project Vault queue; the read-only archive scan
   sets it to `false`).
   - Nothing registered and nothing unwinding → `.terminateNow`. A job cancelled
     earlier from the jobs strip leaves the list at once while its cleanup still
     runs; quit then waits for it without asking (`.waitForCancelledWork`).
   - Otherwise one `NSAlert` names the work ("Keep Music Hub Open" first, then
     "Stop and Quit"); a Vault entry adds that existing recovery records are kept.
   - On confirm `cancelAllForQuit()` calls every cancel. An extra source can
     register a separate `quitCancel`: the Vault's jobs-strip cancel only opens
     its stop sheet, so its quit cancel cancels the waiting requests and stops the
     running transfer directly. The delegate returns `.terminateLater`, so the run
     loop and main-actor cancels keep running.
   - After that stop the archive view model queues no new Vault operation and
     schedules no recovery (`projectVaultStoppedForQuit`): the stopped operation's
     snapshot refresh would otherwise start a Done auto-archive that the exit cuts
     off.
   - A second quit request while the wait runs returns `.terminateLater` and waits
     for the same reply.
   - The coordinator replies (`NSApp.reply(toApplicationShouldTerminate: true)`)
     once `hasUnfinishedQuitBlockingWork` is false or after 5 s. A cancelled runner
     job counts as unfinished until its operation has returned
     (`JobRunning.hasUnfinishedWork`), so helper teardown and partial-file cleanup
     get to run. The deadline stops a cancel that never finishes from blocking quit;
     the process-group backstop below still reaps any helper left after it.
   - The delegate no longer reads the Vault queue count; the Vault reaches quit
     through the center like every other tool.
3. **Process-group backstop (implemented).** `LiveProcessGroupRegistry.shared`
   holds the process-group IDs of helpers that are running right now:
   - The runner records the group right after `posix_spawn` succeeds and forgets
     it as soon as `waitpid` returns for the leader, so a later reap never picks
     up a group whose leader PID may already be reused. The one exception is the
     SIGKILL below, which a running reap sends to its own snapshot on purpose.
   - `AppDelegate.applicationWillTerminate` calls `reapLiveProcessGroups()`:
     SIGTERM to every live group, a poll of up to 1 s for the groups to empty,
     then SIGKILL to any group that still has members. The SIGKILL uses the
     snapshot taken before the SIGTERM, so a descendant that ignores TERM does not
     survive a leader that exited during the grace period.
   - The registry is injectable (`FoundationExternalProcessRunner(processGroups:)`),
     so tests use a private instance.
   - The bounded `Process` probes in `VaultAutomation` stay outside it.

## Options

| Option | Complexity | Pros | Cons |
|---|---|---|---|
| A. More closures on `HubAppDelegateServices` (recorder VM, helper setup) | Low | Smallest diff | Each tool adds another privileged path; lazily created VMs may not exist; misses the next tool |
| **B. Registry in `ShellJobStatusCenter` + `.terminateLater` + live process-group set** | Med | One owner; jobs strip, ⌘. and quit agree; new tools get quit safety by registering | A `listed` flag on job rows; the recorder's cancel must finalize reliably |
| C. `ToolFeature.terminationRequest()` on the protocol | Med | Explicit per feature | Lifecycle moves onto the protocol; every feature re-implements kill logic; lazy sessions answer "nothing" |

B reuses what exists (`setExtraJob`, cancel routing, the runner's signal code) and
puts the process backstop at the one helper spawn point.

## Consequences

- A helper still running at quit is terminated with the app instead of orphaned.
  Quit can block the main thread for up to the 1 s grace period, only when a helper
  is running.
- Known limit: a descendant that a helper leaves running after the helper itself
  exited normally is not tracked (its leader was reaped, so the group is forgotten).
  The runner's own cancel and timeout paths still signal the whole group.
- A helper spawned after `applicationWillTerminate` has reaped gets SIGKILL as soon
  as it is recorded; the app is exiting at that point.
- Quit asks whenever a download, stem separation, conversion or Vault operation is
  running, and waits at most 5 s after confirm. The wait polls every 50 ms on the
  main actor; nothing blocks the main thread.
- Still open: recorder takes and helper installs do not register yet (item 1, the
  `listed` flag). Until they do, a recording or `uv` install at quit is not asked
  about; the backstop still reaps an install's helper.

## Tests

- `ExternalProcessRunningTests.testLiveProcessGroupRegistryTracksRunningHelperAndForgetsFinishedOne`
- `ExternalProcessRunningTests.testReapLiveProcessGroupsKillsRunningHelperAndItsChildren`
- `ExternalProcessRunningTests.testHelperSpawnedAfterReapIsKilledImmediately`
- `HubTerminationSourceTests.testAppDelegateReapsHelpersOnWillTerminate`
- `HubTerminationSourceTests.testAppDelegateDefersQuitToCoordinator`
- `HubTerminationCoordinatorTests` (no work, a running download asks, confirm
  cancels and waits for the unwind, a download cancelled earlier is waited for
  without asking, the deadline, a single reply)
- `ArchiveBrowserViewModelTests.testVaultRefusesNewOperationsAfterQuitStop`
- `ArchiveBrowserViewModelTests.testPendingVaultOperationsAppearAsBlockingWork`
- `ArchiveBrowserViewModelTests.testArchiveScanDoesNotBlockQuit`
