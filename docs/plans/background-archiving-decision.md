# Decision memo: what "Archive automatically" should do

**Status:** Decided: Niko chose **A** on 2026-10-24. Implementation plan: [remove-background-archiving.md](remove-background-archiving.md).  
**Date:** 2026-10-24  
**Source:** finding #8 of the 2026-10-22 architecture review ("Decide the background Vault archiving module"); gap 8
and open question 5 in [architecture-map.md](../architecture-map.md). Facts observed at `c51e10f`.

## The question

Settings → Vault has a switch that promises background archiving, but the app never archives in the background. Should
the app do what the switch says, or should the switch go?

## What a person sees today

- Settings → Vault (`ProjectVaultSettingsView.swift:48-73`): **"Archive automatically"** with the subtitle "Archives
  projects you haven’t touched in a while, or when space runs low", then two steppers that are always shown while the
  Vault is on: "After *n* days untouched" (7–365) and "Or when less than *n* GiB is free" (10–1000).
- With the switch on and Open at login off, a warning says: "Automatic archiving is on, but Niko Music Hub will not open
  at login. Turn on Open at login in General to run copies while you are away." (`LaunchAtLoginControlling.swift:54`)
- Other copy that mentions it: "Kept on this Mac. Automatic archiving skips it.", "Pinned projects are never
  automatically archived", "Archive folder is unavailable. Automatic work is paused."
- `docs/ableton-and-project-restore.md:58, 72` mention an "automatic inactivity window".

## What the code does

- **Nothing reads the switch to archive.** No production code builds a background (`.policy`) candidate, and git history
  shows none ever did. No timer, idle, wake or low-space trigger exists.
- **The only automatic archiving is the Done copy**, and it ignores the switch: after each snapshot refresh,
  `enqueueDoneVaultProjectsIfNeeded` (`ArchiveBrowserViewModel+ProjectVault.swift:212-252`) queues a copy-only archive
  for every Done song without a transfer, Keep Local pin, retry or identity review. It never removes the Active copy.
- The runtime builds the automation policy with the switch hard-coded on (`LiveProjectVaultRuntime+Archive.swift:474`)
  and `isKeepLocal: false` (`:493`); the inactivity and low-space checks (`VaultAutomation.swift:171-183`) are
  unreachable. The days and GiB values reach only a validity check that the UI ranges always pass.
- The switch is read by diagnostics, the login warning (computed and then discarded at launch by
  `VaultLaunchAtLoginReconciler`), settings repair and the recovery bundle import.
- **Latent risk:** `VaultAutomationScheduler` removes the Active copy by default (`removesActiveCopy: true`,
  `VaultAutomation.swift:580`). Only the Done caller overrides it. Any future background wiring that forgets this would
  delete Active folders without asking.
- **A wrong message, whatever you decide:** "Automatic archiving is turned off." is thrown when a *manual* Done archive is
  refused by the rollout gates (`LiveProjectVaultRuntime+Archive.swift:134, 399`; `+Admission.swift:369`). The switch is
  not the cause.

## The constraint that shapes every option

"Removal always asks first" is a product rule (Settings `:95`, the copy-only contract in `ProjectVaultOperating.swift:15-24`,
the bound-authorization model). So background work may only **copy**. A copy frees no space on the Mac; "when space runs
low" can at most prepare verified copies so the existing "Ready to free space" offer appears, and you still confirm each
removal.

## Options

| | A: Remove the switch | B: Make it real, copy-only | C: The switch controls the Done copy |
| --- | --- | --- | --- |
| What you see | The switch, both steppers and the login warning go away. Done songs keep getting a verified copy, as today. | Untouched songs (after *n* days) and, when the Mac is low on space, the oldest songs get a verified copy while the app runs. "Ready to free space" then appears; removal still asks. | The switch is renamed, e.g. "Copy Done songs automatically" (on by default). Off: Done only changes the status; Archive Now still works. The steppers go away. |
| Work | Small: delete the unused paths, three settings rows, the login policy; update 6 docs and the copy | Large: a trigger (timer, launch, wake), a candidate list over the Active root with Keep Local, last-activity detection (Ableton projects are not covered by the CPR date), the queue path through `ProjectVaultOperationCoordinator`, Emergency Stop, new tests and E2E | Small to medium: one setting read in `enqueueDoneVaultProjectsIfNeeded`, the rename, the same deletions as A |
| Risk | Low | Medium-high: background copies of large projects use disk and CPU while you work in Cubase; works only while the app runs; the removal default above must be fixed first | Low |
| Settings | Old settings still load (unknown keys are ignored); older app versions read safe defaults | New fields stay | As A |

## Recommendation

**A**, unless you want a way to turn the Done copy off — then **C**. B solves a problem the Done copy already covers for
finished songs, and it cannot free space without asking anyway.

In every option: fix the "Automatic archiving is turned off." message for refused manual archives, and make the
scheduler's removal default `false` (or delete the scheduler's removal branch if A or C).

## What I need from you

Pick **A**, **B** or **C**. Then I write the implementation plan for it (behavior change: it changes what you see in
Settings, so it is outside the batch approval).
