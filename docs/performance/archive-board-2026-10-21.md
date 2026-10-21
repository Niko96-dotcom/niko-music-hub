# Archive board performance (round 2, 21.10.2026)

## What was merged

`main` holds `perf/r2-combined`: Sol's native board lanes (this report, below) plus the memory work from
`perf/r2-sonnet` (index save by diff, held catalog kept on an unchanged rescan, shared preview reason lists, rescan
result released off the main thread, rescan apply limited to changed songs; Sonnet's own report is on that branch),
a cross-fade for the card hover fill, and the removal of the in-app probe.

The referee measured it from outside the app on the synthetic 10k archive (probe v4, one quiet pass, base = 4 runs,
branch = 1 run, release builds; base is `main` before the merge):

| Measure | Base | Merged |
| --- | --- | --- |
| Fling to the oldest song in the largest lane | never arrives | 188 ms |
| Back from a song's detail page to the board | 301 ms | 84 ms |
| Settled / peak memory after a cached launch | 648 / 763 MB | 340 / 482 MB |
| Settled memory after a first scan | 446 MB | 236 MB |
| Switch to the Archive tool | 184 ms | 161 ms |
| Fling back to the top | 139 ms | 166 ms |
| Open a song's detail page | 172 ms | 188 ms |
| Old-song search hit (typed) | 429 ms | 495 ms |

Known costs: each table row hosts its own card, so a search that shows cards costs about 1.8 ms per card plus
about 2 ms per lane for the table reload; opening a detail page hides the mounted board. An accessibility client
that reads a lane's full child list (3,042 rows) costs the app about 135 ms per read.

# Sol's report (perf/r2-sol)

## Summary

The 10k failure followed SwiftUI lazy-row realization inside the independently hosted board columns: after a rapid fling, a valid jump to the end could leave the oldest card without a layout frame for the entire five-second observation. The baseline failed all 12 repeat-to-end trials; the final implementation passed all 12, with a median 42.8 ms to a fully visible oldest card. Compact Foundation URL values and sharing unchanged songs removed duplicate catalog allocations; native reusable rows preserve the existing SwiftUI cards, and reusing their containers prevents scroll-history allocation growth. Keeping the bounded board hierarchy mounted during detail visits reduced return latency from 190.6 to 81.0 ms (58%); settled physical footprint fell from 641.2 to 367.6 MiB (43%). Detail opening and background scan completion still have measurable costs, documented below.

## Measurement method

> **Note (21.10.2026):** the in-process probe and its runner, `script/archive_perf.sh`, were removed from the app
> after the bake-off, so the app ships no measurement code. They stay in the history of `perf/r2-sol` (added in
> `4bdaf50`); the rerun commands below work only on a checkout of that branch. The referee measures from outside the
> app, and `script/performance/` holds the in-process harnesses that stay outside the product.

- Hardware: Apple M1 Ultra, 20 logical CPUs, 64 GiB; macOS 27.0.1 (26A434), Apple Swift 6.4. All scored app builds are **release**, with warnings as errors and the strict target import check.
- Dataset: frozen generator's **10k** archive, seed 20261018, 10,000 songs and 157,639 files. The largest lane is No Status, with 3,042 songs. The same seeded workflow/collaborator/history database was used throughout. Each scored launch loads the existing index and performs the normal background rescan and watcher setup. No real archive or personal settings were used.
- The app was launched exclusively through `script/bakeoff/app.sh`, using `BAKEOFF_NAME=r02` from the unchanged file and suite `NikoMusicHubBakeoff.r02.10k`. The committed runner (`script/archive_perf.sh`) first requires a successful independent strict build: the frozen launcher's conditional shell function can otherwise continue after a compile error and package a stale binary. Such exploratory launches were excluded.
- The opt-in in-process probe (`Sources/FeatureArchiveBrowser/ArchivePerformanceProbe.swift`) requires the isolated bakeoff suite, dry-run opening, the synthetic root and a request file beside that root. It exercises the actual running app, its native scroll views, its normal detail action and SwiftUI route changes. The shell has no Accessibility or Screen Recording permission; these are **layout/runtime observations**, not screenshot, compositor-presentation or human input measurements.
- Per source checkpoint: **three separate launches, four trials per launch**, with the first trial included. No profiler was attached to scored runs. The probe waits for the full scan apply, index persistence and intelligence work, then allows two seconds and another second after window sizing. The requested content size was 1440×900; the host constrained the actual window to 1440×748, with a 204×508 lane viewport. Other processes on this shared host were not stopped; the reported spread includes that noise.
- Fling: 60 pixel wheel events of −5,000 pixels, delivered to the real scroll view at five-millisecond intervals. The timer includes that injection period and waits up to five seconds for the **entire** oldest card to be inside the actual clip viewport, allowing one point for native pixel rounding. A sliver behind the header does not pass. A separate observation follows 750 ms later.
- Repeat-to-end: scroll to the top, wait 200 ms, jump to the current document end and force window layout while polling for that same full-card condition. A five-second timeout is a failed trial, not a successful five-second response.
- Navigation: call the same `openSongDetail` action as a card, observe the SwiftUI route transaction and force window layout. After 500 ms, return to board and time through its route transaction and first-card layout in an unhidden lane. Trials alternate opening from the newest and oldest ends; returning from the oldest also checks the former remount's scroll-to-top behavior. The first six card rectangles match exactly between all five checkpoints, including the wrapped-title heights: x=8, width=204, y=46/120/201/275/349/423, heights=68/75/68/68/68/75. Retained detail visits hide all eight native lane hosts.
- Memory: `task_info(TASK_VM_INFO).phys_footprint / 1,048,576`, sampled at least 60 seconds after readiness. Actual final observations were 62.97–63.03 seconds; baseline observations were 60.35–60.52 seconds. This includes allocator-held pages. It is not a count of live Swift objects, and the min–max spread is material.
- `catalog_ready` starts at the archive pane's task and ends after the full background scan applies. It is not process startup or first cached paint. `ready` additionally includes persistence/intelligence and the deliberate three-second settling period.

Rerun the current code without GUI automation:

```bash
script/bakeoff/app.sh prepare 10k
for run in 1 2 3; do
  script/archive_perf.sh rerun-$run 4
done
```

Raw scored results are `bakeoff-data/10k/perf-matched-{baseline,catalog,native,retained}-{1,2,3}.json`; each records the running bundle's source SHA, release configuration and PID. The corresponding build/summary logs are `.build/matched-<stage>-<run>.log` and `.build/perf-matched-<stage>-<run>-build.log`. Final-row-reuse results are `bakeoff-data/10k/perf-final-{1,2,3}.json`; the reproduction script labels their equivalent runs `matched-row_reuse-{1,2,3}`. Generated evidence remains gitignored. The source snapshots were restored **in this worktree**, without changing branches or touching another checkout, using the following reproducible procedure from a clean tree. It preserves displaced source files inside `.build/` and restores the starting source in `finally`:

```python
import json, os, pathlib, signal, subprocess, time
root = pathlib.Path.cwd()
final = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
stages = [('baseline','4bdaf50'),('catalog','6fe258d'),('native','abe568f'),('retained','391243c'),('row_reuse','093f2a1')]
stages = [(name, subprocess.check_output(['git','rev-parse',sha],text=True).strip()) for name,sha in stages]
if subprocess.check_output(['git','status','--porcelain'], text=True).strip():
    raise SystemExit('need a clean source checkpoint before changing measurement snapshots')
paths = subprocess.check_output(['git','diff','--name-only',stages[0][1],final,'--','Sources','Tests'],text=True).splitlines()
state = root / '.build/measurement-state.json'
results=[]
def snapshot(sha):
    for relative in paths:
        target = root / relative
        result = subprocess.run(['git','show',f'{sha}:{relative}'],capture_output=True)
        if result.returncode == 0:
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(result.stdout)
        elif target.exists():
            backup = root / '.build/measurement-source-backup' / sha / relative
            backup.parent.mkdir(parents=True,exist_ok=True)
            target.replace(backup)
    state.write_text(json.dumps({'source':sha,'restore_source':final}))
def interrupted(signum, frame):
    raise KeyboardInterrupt()
signal.signal(signal.SIGTERM,interrupted)
try:
    for name,sha in stages:
        snapshot(sha)
        print(f'STAGE {name} {sha}',flush=True)
        for run in range(1,4):
            label=f'matched-{name}-{run}'
            env=dict(os.environ,NMH_SOURCE_COMMIT=sha,NMH_BUILD_ID=f'perf-{name}-{sha[:12]}')
            log=root / f'.build/{label}.log'
            state.write_text(json.dumps({'stage':name,'run':run,'source':sha,'restore_source':final}))
            with log.open('w') as output:
                subprocess.run(['script/archive_perf.sh',label,'4'],env=env,stdout=output,stderr=subprocess.STDOUT,check=True)
            artifact=root / f'bakeoff-data/10k/perf-{label}.json'
            data=json.loads(artifact.read_text())
            metadata=next(x for x in data if x['scenario']=='waiting')
            assert metadata['sourceCommit']==sha and metadata['configuration']=='release',metadata
            assert len([x for x in data if x['scenario']=='detail_to_board'])==4
            results.append({'stage':name,'source':sha,'run':run,'result':str(artifact.relative_to(root))})
            (root / '.build/measured-stages.json').write_text(json.dumps(results,indent=2))
            print(f'DONE {label}',flush=True)
finally:
    snapshot(final)
    state.write_text(json.dumps({'stage':'restored','source':final,'results':len(results)}))
    print(f'RESTORED {final}',flush=True)
```

The table's final measured source is `093f2a1`. The preservation patch `477f9ae` unifies visible-board routing for the existing missing-selection fallback; the timed selected-song routes are unchanged. A separate unprofiled source recheck and two profiling passes verified the complete implementation after that patch. No measured history was rewritten.

## Baseline

Numbers are median (min–max; sample count). All columns are release/10k. UI samples are 12 trials across three launches; memory and scan readiness have three observations.

| Scenario | Baseline `4bdaf50` | Catalog `6fe258d` | Native lanes `abe568f` | Retained board `391243c` | Final row reuse `093f2a1` |
| --- | --- | --- | --- | --- | --- |
| Wheel to a fully visible oldest card | 5677.7 ms (875.6–5893.0; n=12) | 5665.4 ms (734.6–5907.8; n=12) | 1204.4 ms (1102.3–1359.6; n=12) | 1173.7 ms (1078.5–1354.9; n=12) | 1190.6 ms (990.9–1358.2; n=12) |
| Repeat jump to oldest card | 5012.5 ms (5007.5–5017.1; n=12) | 5013.1 ms (5007.6–5027.9; n=12) | 48.1 ms (43.4–71.3; n=12) | 48.2 ms (42.4–76.6; n=12) | 42.8 ms (36.4–65.5; n=12) |
| Detail → board | 190.6 ms (182.1–202.5; n=12) | 165.6 ms (155.4–172.7; n=12) | 259.1 ms (234.3–279.1; n=12) | 80.4 ms (77.4–103.9; n=12) | 81.0 ms (77.2–114.4; n=12) |
| Open detail | 114.1 ms (80.9–159.5; n=12) | 103.9 ms (91.8–158.1; n=12) | 129.0 ms (108.4–154.3; n=12) | 141.7 ms (119.4–165.9; n=12) | 137.1 ms (126.2–173.6; n=12) |
| Full scan apply from pane task | 8352.4 ms (7527.0–14031.6; n=3) | 8128.2 ms (8125.2–8822.8; n=3) | 7974.7 ms (7321.5–11424.2; n=3) | 8462.7 ms (7911.0–9654.0; n=3) | 8710.1 ms (7633.1–8931.4; n=3) |
| Settled physical footprint | 641.2 MiB (636.0–643.0; n=3) | 380.1 MiB (378.5–386.6; n=3) | 377.1 MiB (375.4–484.5; n=3) | 473.4 MiB (388.8–484.8; n=3) | 367.6 MiB (366.7–483.5; n=3) |

| Reachability | Baseline | Catalog | Native lanes | Retained board | Final row reuse |
| --- | --- | --- | --- | --- | --- |
| Wheel, full oldest card | 1/12 | 1/12 | 12/12 | 12/12 | 12/12 |
| Repeat-to-end, full oldest card | 0/12 | 0/12 | 12/12 | 12/12 | 12/12 |
| Detail open / return layout | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 |

All baseline/catalog repeat-to-end values are timeouts; their ~5,010 ms values must not be interpreted as eventual success. The unprofiled baseline return was about 191 ms on this host. Exploratory sampling stretched some returns toward one second; those profiler-affected timings are not used to manufacture a one-second baseline.

## Fixes

### Fix 1: compact and share immutable catalog values

- Commit: `6fe258dbb22c99b9ae67955602515901ddd27a86`.
- Hypothesis: cached decoding and a fresh scan independently allocate equivalent song graphs, while board/lookup caches retain the preceding graph. Stored enumeration URLs also retain filesystem caches, and ordinary Swift URL reconstruction creates large parsed-path representations.
- Change: preserve URL text in fresh compact `NSURL`-backed values, using the existing URL JSON format; share a previous song only when **every field** remains equal. Changed/added/removed songs follow the incoming snapshot. No count cap, stale timestamp, archive write or weaker gate was introduced. Tests cover exact URL encoding, Unicode/directory values, fresh filesystem reads, shared unchanged storage, changed metadata/files, ordering and removals.
- Before → after: settled footprint 641.2 MiB (636.0–643.0; n=3) → 380.1 MiB (378.5–386.6; n=3); return 190.6 ms (182.1–202.5; n=12) → 165.6 ms (155.4–172.7; n=12). Repeat-to-end still failed 12/12.
- Verdict: **kept** for the measured memory reduction; it does not claim to fix lazy-row realization.

### Fix 2: native row realization with the existing cards

- Commit: `abe568f0e516ca766ba2a383ea05de22879a1af6`.
- Hypothesis: the lazy stack's estimated extent and realization could diverge across the nested hosting/clip boundary. The missing final-card frame persisted even at a valid end offset; correcting bounds alone did not repair it.
- Change: an `NSTableView` owns the lane document and reusable cells. Each cell hosts the unchanged `ArchiveBoardSongCard`; cards, copy, actions, keyboard-focus forwarding, context menus and drag payloads remain the existing implementation. Drop landing frames come from the realized native card view. Actual width-constrained natural heights preserve wrapping, six-point gaps and the last-row edge. Sizing follows [Apple's hosting-controller API](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions), with redundant implicit sizing proposals disabled. Height measurements are invalidated for updated content and width; offscreen metadata/Vault changes invalidate table heights too. Tests caught and fixed a wrapped-title clipping prototype before acceptance.
- Before → after: repeat-to-end 5013.1 ms (5007.6–5027.9; n=12) with 0/12 success → 48.1 ms (43.4–71.3; n=12) with 12/12 success; wheel success 1/12 → 12/12. Rebuilding the native board increased return cost from 165.6 to 259.1 ms median; the next fix addresses that measured regression.
- Verdict: **kept together with Fix 3**. Clamping the scroll offset is insufficient without reliable row realization.

### Fix 3: retain the bounded board hierarchy across detail visits

- Commit: `391243cc2b651eb7f224ce62579b54633ba2e127`; preservation follow-up `477f9ae`.
- Hypothesis: returning from detail rebuilt hosting views, controls and intrinsic-size layout even though the column projection was already cached. Samples showed hosting/table sizing and SwiftUI layout work; a fast projection benchmark did not remove this user-facing cost.
- Change: keep the board mounted while detail is shown; hide its native hosts and SwiftUI header, remove hit testing/accessibility, and reset lane scroll positions as the former remount did. Detail still unmounts and flushes edited metadata normally. Board-only commands follow the actually visible page, including the existing fallback after a song disappears. No second owner of selected-song state was added.
- Before → after: native-board return 259.1 ms (234.3–279.1; n=12) → 80.4 ms (77.4–103.9; n=12); relative to the original baseline, 190.6 → 80.4 ms. Repeat-to-end remains 12/12 successful.
- Cost at this checkpoint: detail opening is 141.7 ms versus 114.1 ms baseline; memory at this checkpoint is 473.4 MiB (388.8–484.8; n=3) versus 377.1 MiB (375.4–484.5; n=3) native-only. Retention spends memory and some entry work to avoid the much larger return rebuild.
- Verdict: **kept** for the independently measured return improvement. Final total memory remains below baseline.

### Fix 4: reuse native row containers as well as cards

- Commit: `093f2a1`.
- Hypothesis: final re-profiling still found unnecessary scroll-history allocation. After the same twelve-trial long-scroll profile, `heap` counted **3,020 `ArchiveBoardCardRow` objects but only 43 card cells/controllers**. The custom row delegate created containers without a reuse identifier.
- Change: assign a separate native row identifier and obtain row containers through AppKit's existing reuse queue. This changes neither row contents nor selection/drag behavior. Existing native layout/content/drop tests pass.
- Before → after: the repeated twelve-trial profile now retains **43 rows, 43 cells and 43 hosting controllers**. Scored settled footprint 473.4 MiB (388.8–484.8; n=3) → 367.6 MiB (366.7–483.5; n=3); return 80.4 ms (77.4–103.9; n=12) → 81.0 ms (77.2–114.4; n=12). Both endpoint scenarios remain 12/12 successful. The footprint ranges overlap; the independent object-count reduction establishes the allocation fix rather than relying on the median alone.
- Verdict: **kept**. This issue was found only by the required final scenario re-profile.

### Reverted exploratory attempts

These observations use the earlier exploratory probe where noted; they are not mixed into the scored table.

| Attempt | Observation on release/10k | Verdict |
| --- | --- | --- |
| Clear resource caches on URL value copies | One process: 636.49 → 636.27 MiB after the same seven-trial sequence | Reverted; effectively no gain |
| Reconstruct stored URLs as ordinary Swift URLs | One process: final 632.66 MiB versus 636.49 MiB baseline; heap shifted from resource caches to parsed URL/string storage | Reverted; no useful memory reduction |
| Correct shrinking lazy-document bounds | All five repeat-to-end trials still timed out at five seconds, despite restoring legal offsets | Reverted; fixed the offset symptom, not realization |
| Group cards into batches of eight inside the lazy stack | All five repeat-to-end trials still timed out; some wheel trials also timed out, and return rose to roughly 223–237 ms | Reverted; slower and still incomplete |

## Not done

The work was re-profiled in the same running-app scenarios after the retained-board change and again after row-container reuse. These profiler-affected timing runs are excluded from the scored table.

- **Return still costs 81.0 ms median (77.2–114.4; n=12).** `final-navigation.sample.txt` and `row-reuse-navigation.sample.txt` show remaining main-thread SwiftUI/AppKit layout, display-list updates and platform-view reattachment inside the forced return layout. Keeping the graph avoids reconstruction but does not eliminate framework layout/reattachment. The profile does not support a remaining full-catalog sort as the cause.
- **Detail entry costs 137.1 ms (126.2–173.6; n=12), versus 114.1 ms baseline.** Retention and selection/visibility work spend some entry time to save the larger return rebuild. Detail teardown and edited-draft flushing remain unchanged; saving dirty notes was not timed in this scenario.
- **The accelerated wheel sequence costs 1,190.6 ms (990.9–1,358.2; n=12).** It includes all 60 injected events and their delays. Native cell natural-height measurement (`ArchiveBoardCardCell.measure` → `NSHostingController.sizeThatFits`) remains visible in the sample while rapidly traversing new rows. Only a realized cell's current content/width is memoized; no stale catalog-wide height cache or fixed-height truncation was substituted. The final source recheck passed all four unprofiled endpoint and navigation trials; the final twelve-trial profiling run also passed all endpoints.
- **The full background scan apply still takes 8,710.1 ms from the pane task (7,633.1–8,931.4; n=3).** This is not first cached paint. In the sampled startup interval, 653 of 658 main-thread stack observations were waiting in the event loop; active workers were in song-folder enumeration, preview reading and `NoFollowPath` descriptor checks. Those read-only containment checks were preserved. Index persistence completed about 0.4 seconds after the catalog-ready marker; the later `ready` value also includes deliberate settling.
- **Live catalog storage remains substantial.** Final heap inspection shows one 10,000-song set of preview/version array storage, about 168,883 URL objects and roughly 143 MB of Swift string storage. The row-container count fell from 3,020 to 43; the remaining catalog data and allocator-held pages were not discarded or capped. Scored physical footprint is 367.6 MiB median, with a material 366.7–483.5 MiB spread.

Profile artifacts are under `bakeoff-data/10k/`: `final-launch.sample.txt`, `final-navigation.sample.txt`, `final.heap.txt` and `final.vmmap.txt` before row reuse; `row-reuse-launch.sample.txt`, `row-reuse-navigation.sample.txt`, `row-reuse.heap.txt` and `row-reuse.vmmap.txt` afterwards. `perf-final-source-check.json` is the separate unprofiled recheck after fallback-route preservation. To reproduce profiling, run `KEEP_RUNNING=1 script/archive_perf.sh profile-check 12`, attach `sample <PID> 8 -file <project-local-path>` during its navigation trials, inspect `heap -sortBySize <PID>` / `vmmap -summary <PID>` after timing, then stop through `script/bakeoff/app.sh stop 10k`.


## Risks

- Retaining the board has a memory cost before container reuse, as quantified above. Physical footprint includes allocator-held pages, with a wide final 367–483 MiB range; this is not a hard memory ceiling or a claim that every allocated byte is necessary.
- Cached row measurements are local to a realized cell's current content and width. Updated catalog/Vault values invalidate offscreen heights; tests verify that a previously offscreen long title grows correctly when realized. No persistent derived-data schema or archive safety policy changed.
- The actual running app and native frames were checked on this arm64/macOS host and synthetic 10k archive. Pixel appearance, real pointer drag/drop, keyboard interaction and other macOS/Intel combinations were not manually accepted. Native/drop/navigation/state/design guards and fixture-based behavior tests passed; those are distinct from human UI acceptance.
- No release or publication was attempted. `e2e_user_smoke.sh` was not run because it directly launches a different bundle, contrary to the brief's exclusive launcher rule; the mandatory pre-release acceptance gate remains intact.

Validation: the full `./script/ci.sh` passed on the implementation tree (`.build/ci-candidate.log`), including strict compilation, domain/feature/source guards, self-test, protected-root CLI checks and release-script regressions. The exact final-commit gate is run again after committing this report, with output retained in `.build/ci-final.log`.
