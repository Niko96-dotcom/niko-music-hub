# Archive UI performance — 2026-09-05

This pass follows the [archive/core investigation](archive-performance.md). It preserves
those changes and the unrelated working-tree edits. Three performance changes were retained:

- **Narrow UI updates.** Search text has its own observable input object shared by the board
  and sidebar fields. Keystrokes no longer publish through the whole archive model. Board
  collections/cards compare their actual song, selection, Vault and action-owner inputs;
  unrelated progress updates do not rebuild their controls. Playback and hover remain owned
  by their existing child views.
- **Background live search.** After the existing 200 ms debounce, a serial actor computes
  the same immutable browse projection. Canceled requests cannot publish stale results.
  Immediate search, clearing, filters and catalog changes keep their synchronous semantics.
- **Lazy CPR rows.** Expanding Details creates CPR rows near the viewport rather than every
  version at once. This also defers file-size reads for offscreen rows. All versions and their
  original ordering, Set Main, Hide and Auto CPR actions remain available.

Manual UI work also reproduced a correctness problem in the full app: with a song selected,
`o` was consumed by the Open CPR shortcut while editing search. Printable song shortcuts now
check the actual AppKit text responder as well as SwiftUI container focus.
The resumed desktop check also exposed competing search/board focus flags. They now share
one focus state, and the archive accepts editing-style keyboard interaction. Clicking a card
explicitly returns focus to the archive. This follows the focus interaction model described
in [Apple's focus cookbook](https://developer.apple.com/videos/play/wwdc2023/10162/).

## Measurements

Release builds, Apple M5 Pro, macOS 26.5.2, Swift 6.3.3 / Xcode. The baseline includes the
preceding core improvements and all pre-existing production edits; it is **not bare HEAD**.
Raw samples, source/binary hashes and fixture configuration are in
[ui-performance-results.json](ui-performance-results.json).

The full comparison runs **before → after → after → before**. Each normal workflow has three
warmup iterations followed by 15 measured iterations per process (30 samples per side).
Live-search probes use three warmups and seven measured searches per process (14 per side).
The fixture contains 1,000 songs and 24 CPR versions per song. Selection uses the recent-first
browse list, exercising songs near the end of the catalog as well as the visible list.

| Workflow | Before median | After median | Interpretation |
|---|---:|---:|---|
| Board typing / layout | 30.53 ms | 6.87 ms | 77% less synchronous work |
| List typing / layout | 24.47 ms | 2.17 ms | 91% less synchronous work |
| Board maximum main-loop gap during live search | 170.95 ms | 113.92 ms | 33% smaller interruption |
| List maximum main-loop gap during live search | 94.16 ms | 48.65 ms | 48% smaller interruption |
| Board debounced search through layout | 407.78 ms | 366.19 ms | Includes the unchanged 200 ms debounce |
| List debounced search through layout | 307.09 ms | 299.18 ms | Small change; main-thread availability is the benefit |
| Board selection / layout | 31.08 ms | 29.84 ms | Overlapping ranges; no reliable final speedup claimed |
| List selection / layout | 36.06 ms | 40.00 ms | Overlapping ranges; no speedup claimed |
| List scrolling / layout | 22.79 ms | 22.30 ms | Essentially unchanged; wide ranges |
| Details, 24 CPR versions | 58.68 ms | 29.71 ms | About 2× faster |
| Details, 240 CPR versions | 1,368.57 ms | 30.27 ms | About 45× faster |

The detail comparison uses 20 songs with real disposable placeholder CPR files, 24 or 240
versions each, and 30 measured expansions per side. Collapsing and settling happen outside
the timed expansion. Its 240-version ranges were 1,324.79–1,420.12 ms before and
27.99–35.68 ms after. The fixture files are not genuine Cubase projects and are never opened
in Cubase.

### What the timings mean

The window driver hosts the actual Archive Browser in an AppKit window. Normal measurements
cover model mutation, forced `NSHostingView` layout, display and Core Animation transaction
flush. The harness owns the window size; automatic standalone-host ideal/min/max sizing
probes are disabled. Layout is measured at 1,440 × 900 points, with separate resize exercises.
These are **not GPU frame times, input-to-photon measurements, or a 60/120 FPS guarantee**.

A 2 ms main-run-loop timer records the largest gap during each naturally debounced search.
The driver checks complete result arrays and match explanations against the synchronous
projection. Thread CPU time is recorded as a scheduling-noise control: maximum main-thread
CPU work between callbacks fell from 168.70 to 112.33 ms on the board and 91.94 to 47.64 ms in
list view. Search-result drawing still causes noticeable pauses in the large fixture; it is
not claimed to be hitch-free.

The Mac was also running audio software and background processes. They were left alone.
Alternating order, warmups, raw ranges and CPU measurements help expose variability, but
this is not an idle-machine laboratory result. Earlier exploratory runs were faster in
absolute terms; the table uses the final alternating run rather than selecting the best
numbers. No compile, profiler sampling, CI or other task-owned benchmark ran concurrently
with the reported timed comparisons.

A final optimized-only repeat after the keyboard corrections measured board typing at
**5.78 ms** and list typing at **3.93 ms**. The raw run is included as
`final_optimized_confirmation` in the results JSON. It confirms that the final build retains
low typing cost; it is not a new paired comparison and does not replace the table above.

## Memory, startup and tradeoffs

- The 240-version detail process's measured peak physical footprint fell from **183.55 MiB
  to 47.61 MiB** in the resource-instrumented repeat. For 24 versions it was 49.44 → 42.78 MiB.
  This is the isolated fixture process, not the installed app or a leak test.
- The full browse/search process peaked at about **167 MiB before and 162–163 MiB after**.
  Small process-memory differences are not attributed to a single change.
- Search now has a separate small observable object and an actor. In-flight work retains an
  immutable catalog snapshot using Swift's array sharing. Only one projection executes at
  a time; a canceled computation already executing may finish, while canceled queued calls
  skip their work. This improves main-thread availability rather than eliminating search CPU.
- Board equality checks add comparisons and retain ordinary SwiftUI view inputs. No persistent
  per-song normalization cache or extra serialized catalog is introduced.
- Lazy rows move work to scrolling; height estimates can be refined as rows enter the viewport.
  The full version list remains scrollable. Initial-process/app startup was not measured;
  recorded `first_ms` values are first operations in an already-mounted fixture window.

## Investigated but not retained

- A common equatable wrapper around both board and list collections regressed list scrolling
  and typing. The list version was removed. Only the measured board-specific comparison
  boundary remains.
- List date-chip formatting costs about 14–24 ms for **1,000** chip constructions under the
  observed loads; only a small visible subset renders during scrolling. No formatter cache
  with locale/time-zone invalidation complexity was justified by a row-level bottleneck.
- Detail audio already defers preparation, bounds candidate pages, and uses a bounded,
  deduplicated waveform cache. Playback timers update their child views. No new audio/DSP
  optimization was supported by this UI pass.
- Analytics, output inbox, converter, downloader, recorder and stem UI paths were inspected.
  Existing lazy lists, cached snapshots and background processing cover the obvious repeated
  work; no comparable measured low-risk UI change was established there.
- Further board virtualization or a broad observation-framework migration would need stronger
  evidence and more drag/focus testing. They are not asserted to be impossible improvements.

The pass stops at the remaining evidence boundary, not at a claim that every possible UI
optimization has been exhausted.

## Verification and manual coverage

- The final source tree passed `./script/ci.sh`: **1,171 XCTest tests, five runtime skips,
  zero failures**, plus **54 Swift Testing tests**. The normal host-only CoreAudio exclusions
  remain. `git diff --check` also passed.
- Added focused regression tests cover separate search-input publication, debounce snapshots,
  cancellation and out-of-order completion, immediate reset, projection equivalence, board
  equality inputs and text-responder shortcut guards.
- After the Mac was unlocked, the **final source tree passed strict E2E**, including the
  fixture archive/recorder scenarios, denied-write probe, unchanged-archive checks and
  AX-visible public first-run content. The previous locked-screen failure remains in the
  earlier log. Final logs are `.build/performance-ui/ci-unlocked-final.log` and
  `.build/performance-ui/e2e-unlocked-final.log`.
- Manual fixture checks exercised board selection, preview play/pause and advancement,
  selection stopping the old preview, detail opening, deferred duration/waveform display,
  scrolling through all 240 versions, Set Main and Hide, Escape, no-match search and clearing.
  In the full app with fixture settings, typing `o` with a selected song and replacing search
  with `neon hook` (including its space) passed after the shortcut fix.
- The final full-app fixture passed **search → physical card click → Space starts playback**.
  Search with a selected song preserved `neon hook`, including its letters and space. List
  search also updated correctly. Changing the disposable song's status through Song info
  moved its card and updated column counts and stage labels correctly.
- Automated drag attempts did not establish a completed drop. A subsequent **physical user
  drag succeeded**, confirmed in AX: Neon Hook moved to Songstarter/Beat, with column counts
  changing to eight and one. The user reported rough animation both while following the
  pointer and after release. Thus **drop functionality is verified; animation quality remains
  unresolved**. The commit is on hold for that investigation. Stage/projection tests do not
  substitute for pointer-motion coverage.
- Final full-app checks launched the exact built executable directly with explicit fixture
  environment variables, then attached computer-use to the distinct fixture bundle. Earlier
  computer-use auto-launch attempts produced inconsistent lifecycle/focus behavior; they are
  not the basis for the passing keyboard result. Normal installed-app startup is not certified
  by this pass. Temporary key tracing was removed before final gates and manual checks.
- Original tracked working-tree changes were checked against the saved starting patch.
  Removing this pass's hunks from the two already-dirty view files reconstructed their saved
  starting bytes. Unsuccessful performance experiments were removed without resetting other
  changes.
- The scoped commit candidate was also tested in a separate checkout containing only this
  pass's changes over the original HEAD. Its CI passed **1,177 XCTest tests** (five skips)
  plus **54 Swift Testing tests**, and strict UI E2E passed. The test count differs because
  unrelated test edits remain outside the candidate. Logs are
  `.build/performance-ui/ci-scoped-commit.log` and
  `.build/performance-ui/e2e-scoped-commit.log`. These were the earlier scoped gates. The final scope results are recorded below.

## Drag follow-up

The initial `board_status_update_layout` metric changes a scan-progress message; it does
**not** measure a workflow-stage change. A new `--stage-only` mode calls the real
`updateWorkflowStatus`, persists metadata in disposable SQLite, and renders the board. It
verifies the stored and displayed stage afterward. This covers application work on release,
not native drag-image tracking, animation FPS or input-to-photon latency.

With 24 CPR versions per song and the same 1440×900 fixture window, an alternating
before/after/after/before comparison (three warmups and 15 samples per process) produced:

| Catalog | Before median (range) | After median (range) |
|---|---:|---:|
| 20 songs | 18.26 ms (8.23–19.73) | 16.27 ms (7.30–17.90) |
| 1,000 songs | 54.84 ms (45.42–58.84) | 43.73 ms (35.71–45.45) |

This finds no regression in that scripted path; it does not resolve the user's observation
on the nine-song full-app fixture. A separate alternating current-code configuration check
at 20 songs measured 17.46 ms using Debug modules and 16.49 ms using Release modules. Their
ranges overlap; build configuration is not established as the cause of the rough animation.
Raw samples are in [drag-performance-results.json](drag-performance-results.json).

Two CPU captures (45 seconds and an extended recording interrupted after about three
minutes) saw only the idle window. Fixture status history confirms the user's actual drops
preceded those windows. These recordings are **not profiles of the reported stutter** and
support no bottleneck claim. A subsequent 60-second capture starting at **13:47:55 Europe/Berlin** did contain
real drags: the isolated database records 21 stage changes between 11:48:03 and
11:48:40 UTC. Of 50,491 main-thread samples, 46,364 end in `mach_msg2_trap`.
The workflow-update function appears in 20 inclusive samples; `dropUpdated` in 53.
The native drop-animation transaction appears in 7,376 samples, including nested
run-loop waits. These counts are **not CPU time, per-drop latency, or FPS** and do
not establish an operating-system defect. Footprint was 47.2 MiB, peak 51.1 MiB.

This rules out neither rendering hitches nor perceived animation problems. A
separate Animation Hitches capability test worked, but the live capture encountered
low disk space. The recorder failed to finalize after stopping and was terminated with its child.
Only task-owned disposable capability trace, scratch-checkout build output, and the
failed recorder's exact 5.1 GiB temporary ktrace were removed. About 6.1 GiB became
available. The CPU capture predates the observed disk-space failure; the later
frame attempt is not valid evidence.
A 20-second retry after the user confirmed readiness also exhausted disk space
(starting with 6.1 GiB free), and Instruments logged CoreData SQLite error 14.
Four fixture status changes were recorded at 12:07:01–12:07:06 UTC, but the frame
trace could not be finalized and is unusable. The task-owned recorder was terminated;
its exact temporary files were cleared, leaving approximately 4.1 GiB free.
The recording overhead and disk exhaustion also confound perceived performance
in that attempt. The resumed-session real database and WAL still match their
pre-recording SHA-256 and timestamps; this does not undo the earlier isolation incident.

At that point, these profiles had not justified an additional production optimization.
**Native drag smoothness was still unresolved.** Those measurements and gates alone
did not establish a fix. Further frame profiling needed
a recording configuration that stays within available space; do not repeat the broad
Animation Hitches template under these conditions.
After the user freed space, a retry started with **114 GiB available**. The
40-second recording saved and exported successfully (3.7 GiB final trace), but
contained an idle app: two CPU samples, no CoreDrag frames, and no fixture stage
changes. A clean restart then cleared the fixture's stale cache-write error and
restored its persisted stage distribution (4 No Status, 3 Songstarter/Beat, 2 Song).

A subsequent 30-second automated-drag recording also saved and exported (1.9 GiB).
It contains 123 CPU sample rows, 72 with CoreDrag in the stack. Automated drops were
inconsistent, and the confirmed successful move occurred at 13:53:46 UTC, after
that trace ended at 13:53:12 UTC. It therefore does **not** establish successful-drop
or landing-animation performance. Its `hitches` table spans the whole interval
with blank Potential Issue descriptions; raw row counts are not presented as
verified visible stutters. No additional product changes were made from these traces.

Apple distinguishes [commit and render hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app);
CPU activity, compositor rows, and perceived drag smoothness are separate evidence.
The frame captures resolved the tooling/storage failure, not the reported animation
problem. Further comparisons must include the actual gesture and successful drop
inside the timed interval, using the same inputs and capture conditions.

The subsequent synchronized physical capture **did include a successful drop**.
It ran from 16:35:06.970 to 16:35:35.030 Europe/Berlin (28.060 seconds). The isolated
history records No Status → Songstarter/Beat at 14:35:31 UTC; the controller stopped
recording three seconds after detecting that change. Moves at 14:35:38 and 14:35:43
were outside the trace and are excluded. Saving and XML export completed successfully.

Instruments recorded two 16.667 ms hitches: one before the gesture (10.447 seconds
into the trace), and one near hover/gesture onset (23.597 seconds). **No hitch was
recorded during landing in this run.** There were 153 CPU sample rows, 48 with
CoreDrag in their stacks, and 129 ms of main-thread sample weight. Framework hover
and hit testing accounted for much of the sampled work; the app's `dropUpdated`
path had 3 ms of inclusive sample weight. Sample weights are not drop latency.

This is one gesture in an already-running process, not a repeated before/after
comparison. It does not establish that the user's perceived roughness is fixed,
and it does not justify a particular low-risk application-code optimization. No
new drag change had been made at that point. The subsequent native landing change
and user assessment are recorded in the follow-up below.
The trace, exported tables, per-sample stacks, and stop receipt are saved under
`.build/performance-ui/drag-physical-confirmed-before*` and
`.build/performance-ui/drag-physical-confirmed-controller.json`. The local recording
controller is `.build/performance-ui/record-confirmed-drag.py`: it validates the
fixture process and isolated settings, polls only fixture status history, stops after
landing time, and guards disk headroom. For manual reproduction, start the recorder
before the gesture and press Ctrl-C three seconds after a confirmed stage change.

The valid CPU trace is `.build/performance-ui/drag-live-confirmed-sample.txt`.
After identifying the PID of an already-running isolated fixture, repeat with:

```bash
sample "$FIXTURE_PID" 60 1 -file /tmp/nmh-drag-sample.txt
xcrun xctrace record --template 'Animation Hitches' --attach "$FIXTURE_PID" \
  --time-limit 20s --no-prompt --output /tmp/nmh-drag-hitches.trace
```

Run these separately, with repeated physical drags during each recording and ample
free disk space. Do not interpret idle captures as drag measurements. Raw Instruments
traces can contain process environment and local paths; keep them local and out of Git.

## Fixture isolation incident

The requested real-data boundary was breached during manual verification. At **2026-09-05
12:09:46 Europe/Berlin**, computer-use observation after quitting the isolated full-app
instance unexpectedly relaunched the normal app without its fixture environment. The process
was stopped when this was observed. Read-only inspection found the real archive scan-cache
timestamp updated to **10:09:47 UTC**, and **11 `song_metadata` rows** updated at
**10:09:48 UTC**. Prior contents were not snapshotted, so their exact changes cannot be
reconstructed and no speculative rollback was attempted.

No music-file action was sent to that unisolated instance. Its latest workflow-status change
remains August 10; the latest Vault-transfer update remains in August, and there are zero
restore records. Thus the audit found **no new recorded Vault transfer, restore or workflow
status activity**. This does not exclude other automatic startup writes. The real cache and
metadata writes are an exception to the requested isolation, not a successful safety check.

Further full-app checks use a separate, ad-hoc-signed fixture bundle identifier with isolated
settings, fixture root, dry-run opens and disabled watching in its `LSEnvironment`, so a relaunch
keeps those settings. The product bundle identity was not changed. All task-owned app processes
were stopped; known interrupted temporary fixture roots and their isolated preferences were
cleaned. The audit aggregates are retained in `.build/performance-ui/boundary-audit.json`.

The resumed unlocked session's read-only audit found the real database file's SHA-256 and
mtime unchanged. Its WAL timestamp remains 10:09:50 UTC, and the scan, metadata, transfer and
restore aggregates still match the earlier audit. These checks found no additional changes
to that database during the resumed session; they do not undo the incident or certify every
possible user-data location. Evidence is in `.build/performance-ui/unlocked-data-audit.json`.

## Drag smoothness follow-up (2026-09-05)

The first presentation candidate uses a stable compact native drag preview, confines hover
animation to the background fill (100 ms), and scopes a 180 ms column reflow and subtle card
insertion transition to accepted drops. Workflow payloads, validation, persistence, card
controls and archive restrictions remain intact. Reduce Motion disables these animations.
The user tested it and reported **landing still rough**; this is not a completed smoothness fix.

Repeated release stage-update measurements used 20/1,000 songs with 24 CPR versions, three
warmups and 15 measured iterations per process, two runs per variant in alternating order:

| Songs | Before run medians (ms) | First candidate run medians (ms) |
| --- | --- | --- |
| 20 | 13.39 / 8.22 | 8.19 / 8.19 |
| 1,000 | 55.71 / 36.22 | 36.05 / 36.52 |

The first baseline run drifted; the final warm baseline overlaps the candidate. **No reliable
throughput improvement is claimed.** This probe covers synchronous metadata and layout work,
not the native drag preview or the settling animation. The first candidate passed CI (1,171
XCTest cases, five skipped; 54 Swift Testing cases) and strict user E2E. Its source and fixture
Mach-O UUID and file-backed sections matched; the fixture has its own verified ad-hoc signature.

The synchronized after-profile stopped at its disk guard before a confirmed drop, then failed
while saving with `Could not trim file: No space left on device`. It is not a valid after result.
The recorder exited; its exact unused 21,415,499,224-byte raw temporary recording was removed.
No further broad Animation Hitches recordings are being attempted. The real archive database
and WAL hashes/mtimes still matched the earlier boundary snapshot after this failure.

A minimal transaction probe confirmed that the cache's `onReceive` does receive the explicit
animation transaction. A subsequent AppKit destination experiment supplies the actual card
frame to the native drag manager before accepting a drop. This uses Apple's documented
[animatesToDestination contract](https://developer.apple.com/documentation/appkit/nsdragginginfo/animatestodestination).
The native destination synchronously validates the current song and workflow policy, updates
status through the existing metadata path, forces the target column's final layout, and supplies
that card frame to AppKit. Same-column drops remain non-mutating and can settle back into their
current position; auto-scroll remains active for valid cards. Geometry collection is not
observable state. Hosted content changes only when column, selection, Vault presentation,
target highlight or appearance inputs change. A card click explicitly returns keyboard focus
to the board across the native view boundary.

The first native implementation increased stage-layout cost (a paired 20-song run measured
10.36 ms before vs 19.20 ms after), so that implementation was revised. After disabling
redundant intrinsic sizing and avoiding unchanged hosted-content updates, two alternating
runs per variant measured:

| Songs | Prior SwiftUI candidate run medians (ms) | Native candidate run medians (ms) |
| --- | --- | --- |
| 20 | 13.72 / 12.22 | 9.81 / 15.85 |
| 1,000 | 47.36 / 42.95 | 39.90 / 44.21 |

These ranges overlap and do not establish a throughput improvement. The stage probe still
measures model mutation plus layout, **excluding** the native destination callback's extra
projection/layout and macOS's animation. Native callback overhead and animation frame pacing
have not been quantified. The native host adds one hosting view per workflow column and frame
preferences for realized cards; its memory/startup delta has not been isolated. The final physical landing check was acceptable to the user; the added native
view and callback costs remain explicit tradeoffs.

Three behavioral tests cover revalidation, Reduce Motion, the native frame callback, and
obtaining a newly inserted card's frame from real SwiftUI layout before the callback returns.
The final revision passed CI (1,174 XCTest cases, five skipped, zero failures; 54 Swift Testing
cases) and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh`. The gated app and final isolated
fixture have matching Mach-O UUID/file-backed sections and a verified fixture signature.
Physical card click after focusing search, then Space to start and pause preview, passed in
that final fixture. AX-only button activation does not exercise the ancestor tap gesture and
was not used as physical-click proof. After trying the final fixture, the user replied **“yeah i think its fine now”**.
This records a qualitative acceptance of the landing, not a measured frame-rate or latency win.

The unused raw files for the completed earlier recordings were also removed after checking
that no recorder or open file handle remained: 61,053,534,840 bytes. Saved trace bundles and
exported measurements remain. Available space after cleanup was 73 GiB.

Visual settling deliberately takes 180 ms, while status mutation/persistence remains immediate.
The preview contains title and stage; the full card stays on the board. Native session timing
belongs to macOS. Memory/startup deltas and repeated native before/after frame timings have not
been established. Local raw receipts are under `.build/performance-ui/smooth-*` and
`native-landing-*`; those are not release approval.

Final search confirmation on the native landing revision used 1,000 songs, 24 CPR versions,
three warmups and seven measured searches in one after/before process pair. Median maximum
main-runloop gaps were **164.32 → 114.44 ms on the board** and **91.21 → 44.72 ms in the list**.
End-to-end debounced search latency was 399.58 → 366.67 ms (board) and 304.23 → 297.88 ms (list).
These agree with the earlier direction of improvement, but one confirmation pair does not
replace the earlier repeated comparisons. Runloop gaps are not native drag frame rates.
The board still has material main-thread work when applying a large result set; this pass
does not establish that no further worthwhile optimizations exist.

## Final local scope verification

After the user accepted the native landing, the complete performance-only candidate was
reconstructed over the original HEAD in `.build/performance-commit-check`, excluding unrelated
working-tree edits. It passed `./script/ci.sh`: **1,180 XCTest cases, five skipped, zero failures**,
plus **54 Swift Testing cases**. Strict E2E also passed. Logs are
`.build/performance-ui/ci-scoped-native-final.log` and
`.build/performance-ui/e2e-scoped-native-final.log`. This clears the authorized local commit;
it is not a push, deployment or release approval. The user's manual check used the combined
working-tree fixture, not an exact-commit release build.

## Reproduce

Run from the repository root in a logged-in macOS desktop session. The benchmark opens a
clearly labeled fixture window and writes JSON to stdout; compilation and progress go to stderr.

```bash
./script/benchmark_archive_ui.sh > /tmp/nmh-ui-1000.json
./script/benchmark_archive_ui.sh 200 > /tmp/nmh-ui-200.json
./script/benchmark_archive_ui.sh --search-only > /tmp/nmh-ui-search.json
./script/benchmark_archive_ui.sh 20 --detail-only --versions 24 > /tmp/nmh-detail-24.json
./script/benchmark_archive_ui.sh 20 --detail-only --versions 240 > /tmp/nmh-detail-240.json
./script/benchmark_archive_ui.sh 20 --stage-only > /tmp/nmh-stage-20.json
./script/benchmark_archive_ui.sh 1000 --stage-only > /tmp/nmh-stage-1000.json
./script/benchmark_archive_ui.sh 20 --interactive --versions 240
./script/ci.sh
NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh
```

The interactive mode creates quiet synthetic preview WAVs and placeholder CPRs in a temporary
root, with isolated settings and output paths. Close the fixture window when finished. It is
for functional checks; audio playback is excluded from the timing fixtures. Do not run the
interactive fixture or correctness gates concurrently with performance measurements.

`script/benchmark_archive_ui.sh` builds optimized modules with testing visibility solely for
fixture injection; no benchmark runtime is embedded in the product. It links only object files
listed in SwiftPM's current output map, avoiding stale objects from removed experiments.

Exact local comparison binaries, original source copies, starting dirty patch, profiles and
logs are retained under `.build/performance-ui/` and are gitignored. `ui-before` / `ui-after`
are the alternating comparison binaries. `ui-detail-before` is the detail baseline. A clean
checkout of HEAD alone will not recreate the dirty baseline; preserve the starting patch and
source hashes when archiving or repeating this comparison.

No deployment, installation into Applications, push or publication was performed. The real
app-cache and metadata exception is documented above. These checks are not release approval
or cloud/real-project recovery UAT.
