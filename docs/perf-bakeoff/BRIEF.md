# Performance task (round 2)

## The task

> Large archives still feel broken in places. Flinging a long board column can leave it blank so the
> oldest songs never appear, going back from a song's detail to the board takes close to a second, and
> the app holds far more memory than it needs. Find why, fix it without changing what the user sees, and
> prove each fix with before and after numbers on the 10k archive.
>
> Base your decisions on measurements of the actual running app, and verify improvements in the same
> user-facing scenarios. Before finishing, re-profile those scenarios and investigate any substantial
> delays that remain, even if individual component benchmarks already look good. Stopping early is worse
> than running long; if you stop, list what is still slow, with numbers.

## How you work

- Work alone until you are done. Nobody will answer questions. Make reasonable choices and write them
  down in your report.
- You are in a git worktree on your own branch. Commit to this branch only. Do not push, merge, rebase
  onto another branch, switch branches, or touch any other checkout or folder outside this worktree
  (build caches excepted).
- `AGENTS.md` and the docs it points to are binding: architecture, module boundaries, the UI design
  contract, SwiftUI state ownership, the rules table. If a rule blocks a fix, keep the rule.
- Speed only: no feature changes, no visible behavior changes, no stale data (a cache must stay
  correct when the archive changes), no weaker safety checks. The app stays read-only toward archives.
- Commit only green states. Small, coherent commits with clear messages.

## Running the app

Run the app only through `script/bakeoff/app.sh`. Your run name is already in the file
`BAKEOFF_NAME`. Never start `dist/NikoMusicHub.app`, `/Applications/Niko Music Hub.app`, or any build
with your real settings, and never point the app at a real music folder.

```bash
script/bakeoff/app.sh prepare 10k          # synthetic 10,000-song archive + isolated settings (also: 1k)
script/bakeoff/app.sh launch 10k release   # builds, starts the app, prints PID=...
script/bakeoff/app.sh stop 10k
script/bakeoff/app.sh reset 10k            # forget the index: the next launch does a first scan
```

The synthetic archive spans 2010 to 2026 with project versions, mixdowns, stems, autosaves, workflow
status, notes, collaborators and status history. It lives in `bakeoff-data/` (gitignored).

This shell has no Accessibility or Screen Recording permission, so you cannot drive or screenshot the
UI. Plan your measurements with that in mind.

## Frozen files

Do not change anything under `script/bakeoff/` or `docs/perf-bakeoff/` except
`docs/perf-bakeoff/PERF-REPORT.md`. Do not edit `BAKEOFF_NAME`.

## Done means

1. `./script/ci.sh` passes on your final commit, with no compiler warnings.
2. `docs/perf-bakeoff/PERF-REPORT.md` is filled in and committed (use the template in that file).
3. Every fix you kept has a before and after measurement you can reproduce, and the report says how.
   A fix that did not help is reverted and listed as such.
