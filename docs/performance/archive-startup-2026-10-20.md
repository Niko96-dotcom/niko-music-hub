# Performance report

Run name `c06`, branch `perf/sonnet`, base commit `ccc65f1`. Everything below is the release configuration
(`swift build -c release`), measured on one Apple M1 Ultra (20 cores, 64 GB, macOS 27.0.1, Swift 6.4), on the
synthetic bake-off archive: **10k** = 10,000 song folders, 157,639 files, a 130 MB cached index database
(10,000 cached songs = 110 MB of JSON, 6,958 metadata rows, 24,293 status-history rows, 16 collaborators);
**1k** where stated. Ranges are min–max, `n` is the number of samples.

## Summary

The real gap was in loading, not in drawing. With the original code a 10,000-song archive needed **17 s** before
the first cached song appeared and **48 s** before the launch rescan finished, froze the main thread for up to
**1.6 s** when that rescan landed, took **3.4 s** to open Analytics and grew to 1.5–2.2 GB while scanning. The cached
index was decoded one row at a time (with a Calendar and TimeZone built for every date), every cached song was
re-classified and re-ranked on one thread with a regular expression compiled per call (about 14 s of the 16.5 s
cache load), the scan
walked song folders one by one with no autorelease pool, and the main thread then compared the whole catalog with
itself several times and resolved symlinks for all 10,000 folders on every catalog update. I measured each of these
with `sample`, fixed them one at a time (regex compiled once, per-song work on several threads with a thread budget
that I tuned from measurements, a strict parser for the one timestamp spelling the app writes, off-main
intelligence, cheaper sorts and comparisons) and checked every fix against the commit before it with alternating
runs and an output digest that proves the data is identical. On 10k the cached index now appears after **2.6 s**
(6.5×), the rescan finishes in **8.8 s** (5.5×; 5.7 s alone, 7.4× against the 42 s original), the worst main-thread
stall fell from 1.65 s to 0.46 s, Analytics opens in 0.16 s (21×), search is 3× faster, moving a card is 2× faster and
memory after launch is half. Nothing was made slower except total CPU seconds at launch (+19 %, more cores busy for
a shorter time); steady scrolling, opening a song and the tool screens were already within a frame or two and were
left alone.

## Measurement method

**No UI automation.** This shell has no Accessibility or Screen Recording permission, so I measured what runs
under the UI instead, with tools that live in `script/performance/` and were added by this branch:

| Tool | What it does |
| --- | --- |
| `archive-startup.swift` (`script/benchmark_archive_startup.sh startup`) | Headless phases against a **copy** of the isolated database: snapshot decode, metadata load, cache load (decode + merge + normalize), full scan, cache save, status history, Output Inbox, and in-memory phases (sort, board projection, collaborator/duplicate/missing-audio pass, analytics snapshot, search index and queries). Reports wall and process-CPU time per run and an FNV-1a **digest of the output**, so "faster" is only claimed where the digest is identical. |
| `archive-launch.swift` (`… launch`) | One in-process launch: builds `ArchiveBrowserViewModel` the way `AppComposition` does (settings with one scan root, the real SQLite stores on a database copy, cached index, then the background rescan), hosts the real `ArchiveBrowserView` in an `NSHostingView`, records the timeline (model init, cached songs published, scan finished), a 2 ms main-run-loop heartbeat (stalls), then times interactions (open board/list, jump and wheel scrolling to the oldest songs, search old/recent/absent, open old/recent song, sort/shelf/filter, move a card, apply an unchanged scan result, open Analytics). Interaction times are model mutation + `NSHostingView` layout + display + `CATransaction.flush()`; they are **not** GPU frame times. |
| `archive-tools.swift` (`… tools`) | First-open cost (`makeView` + first layout) of the five tool screens. |
| `window-probe.swift`, `real-launch.sh` | The real bundle, launched through `script/bakeoff/app.sh`: time from process start to first on-screen window (reads only window owner/layer/bounds), process CPU, RSS curve. |
| `build-commit-binaries.sh`, `ab.sh`, `compare_phases.py`, `compare_runs.py` | Build the harness against `Sources/` of any earlier commit (`archive-startup-<tag>`, `archive-launch-<tag>`), run two of them **alternately** (A, B, A, B …) and summarize with medians, min–max, n and digest equality. |

**Noise control.** The Mac was shared with eight other agents' builds and runs plus Backblaze and Time Machine
(load average 6–15, `bztransmit` at ~100 % CPU), so absolute numbers drift between sessions (the same original
code measured 15.5–16.5 s for the cache load in different hours). Every before/after below is therefore from
**alternating runs in one session**, 3 rounds, medians of all samples, with process CPU time next to wall time,
and the harness runs at the app's QoS (user-interactive main thread, user-initiated tasks; a shell-launched
process starts at utility QoS, which the scheduler can put on efficiency cores). Where two numbers for the same
thing differ between tables it is because they come from different sessions.

**Reproduce** (all from the worktree root; `script/bakeoff/app.sh prepare 10k` first, then launch the app once with
`script/bakeoff/app.sh launch 10k release` and `stop` it after the scan so the cached index exists):

```bash
export NMH_BENCH_DATABASE="$(script/bakeoff/app.sh paths 10k | sed -n 's/^DATABASE=//p')"
script/performance/build-commit-binaries.sh base  ccc65f1          # original code, current harness
script/performance/build-commit-binaries.sh final HEAD             # this branch
script/performance/ab.sh startup /tmp/ab/H 3 base final --runs 5 --warmups 1 \
    snapshot-load metadata-load cache-load status-history analytics-history cache-save inbox-load
script/performance/ab.sh startup /tmp/ab/S 3 base final --runs 2 --warmups 1 scan
script/performance/ab.sh startup /tmp/ab/M 3 base final --runs 7 --warmups 1 \
    sort-recent board-projection intelligence analytics search-index search
script/performance/ab.sh launch  /tmp/ab/L 3 base final --timeout 300
python3 -I script/performance/compare_phases.py /tmp/ab/H base final    # likewise S, M
python3 -I script/performance/compare_runs.py   /tmp/ab/L base final
script/performance/real-launch.sh /tmp/real.json                        # real bundle; see the header for A/B
```

Each fix was measured the same way against its parent commit (`build-commit-binaries.sh s5 a7bd988` …); the
commit list below gives the hashes.

## Baseline

Original code (`ccc65f1`), release, 10k unless noted; alternating-run sessions on the evening of 19 Oct 2026.

| Scenario | Dataset | Median | Spread (min–max or p90) | Runs |
| --- | --- | --- | --- | --- |
| Cached songs visible after launch (real view model) | 10k | 16.83 s | 16.77–16.91 s | 3 |
| Launch rescan finished | 10k | 48.0 s | 45.1–48.4 s | 3 |
| Cache load (decode + metadata + normalize), headless | 10k | 15.54 s | 15.36–16.26 s | 15 |
| Snapshot decode, headless | 10k | 1.89 s | 1.80–1.95 s | 15 |
| Metadata load (6,958 rows) | 10k | 477 ms | 461–487 ms | 15 |
| Full scan of 10,000 folders, headless | 10k | 42.2 s | 41.8–43.6 s | 6 |
| Cache save of an unchanged catalog | 10k | 1.25 s | 1.23–1.30 s | 15 |
| Main thread: worst stall during launch | 10k | 1,647 ms | 1,638–1,683 ms | 3 |
| Main thread: time lost to stalls > 50 ms | 10k | 3,318 ms | 3,278–3,514 ms | 3 |
| Main-thread CPU during launch | 10k | 3,314 ms | 3,306–3,535 ms | 3 |
| Footprint after launch (in-process) | 10k | 1,458 MiB | 1,457–1,525 MiB | 3 |
| Real app: first window / peak RSS | 10k | 2.5–2.9 s / 1.45–2.23 GB | single runs | 3 |
| Open Analytics | 10k | 3,362 ms | 3,361–3,454 ms | 3 |
| All status history (Analytics input, 24,293 rows) | 10k | 1,537 ms | 1,511–1,583 ms | 15 |
| One song's status history ×50 (indexed) | 10k | 6.2 ms | 5.9–6.7 ms | 15 |
| Apply an unchanged scan result on the main actor (board / list) | 10k | 825 / 866 ms | 818–837 / 855–904 ms | 3 |
| Immediate search, old material (board / list) | 10k | 317 / 298 ms | 310–338 / 289–308 ms | 3 |
| Search, absent query (board / list) | 10k | 269 / 222 ms | 260–290 / 222–238 ms | 3 |
| Open board / open list | 10k | 365 / 59 ms | 346–459 / 56–127 ms | 3 |
| Move a card (status change), board / list, old song | 10k | 281 / 289 ms | 274–301 / 284–315 ms | 3 |
| Wheel scroll, 120 pt steps, top / oldest songs (board / list) | 10k | 6 / 6 ms, 6 / 7 ms | within 1–2 ms | 3 |
| Open an old / a recent song's detail | 10k | 59 / 79 ms | 59–119 / 72–139 ms | 3 |
| Output Inbox list / refresh, 2,000 entries | — | 11.1 / 17.4 ms | 10.8–11.6 / 16.9–19.3 ms | 15 |
| Cached songs visible / rescan finished | 1k | 1.92 s / 3.37 s | 1.91–2.65 / 3.35–4.19 s | 3 |
| Cache load / full scan, headless | 1k | 1.52 s / 2.75 s | 1.49–1.54 / 2.56–3.35 s | 15 |
| Tool screens first open (BPM, Converter, Recorder, Downloader, Stem) | — | 31 / 39 / 39 / 37 / 48 ms | 5 runs each | 5 |

## Fixes

Commit order. "→" is the parent commit's binary against this commit's, alternating runs, same session. Digest
"same" means the harness output (songs, histories, scan results, search results with scores and summaries) hashed to
the same value before and after.

### Fix 1: Compile the filename regular expressions once

- Commit: `71c7c3c`
- Hypothesis: loading the cached index spends most of its time re-classifying and re-ranking every song
  (`PreviewAutoSelectionNormalizer`), and `sample` shows `NSRegularExpression.init` and ICU regex compilation near the top:
  `String.range(of:options: .regularExpression)` and `replacingOccurrences(...)` compile per call and the system cache
  thrashes across ~20 patterns, and `PreviewFilenameParser` even built an `NSRegularExpression` per call.
- Change: `CompiledRegex` (one compiled pattern per call site, `NSRegularExpression` is immutable and thread-safe) in
  `PreviewFilenameParser`, `PreviewSongIdentity`, `PreviewFilenameSemantics`, `SongTitleResolver`,
  `CPRVersionDetector`. `CompiledRegexTests` pins that every pattern answers exactly what the string APIs answer over
  40 filenames (separators, dates, tempo tags, accents, emoji, line breaks).
- Before → after: cache load **16,486 ms (16,123–17,581, n=9) → 10,625 ms (10,479–10,841, n=9)**, 1.55×, digest same.
- Verdict: kept.

### Fix 2: Normalize cached songs on all cores

- Commit: `dd589b8`
- Hypothesis: the remaining ~8 s is per-song pure work on one thread.
- Change: `PreviewAutoSelectionNormalizer.normalized(_:)` maps with `ParallelMap` (order-preserving, thread budget; the
  budget is 12 here because this work scales to ~16 threads: 9.3 s at 1 thread, 2.1 s at 8, 1.7 s at 16).
- Before → after: cache load **10,700 ms (10,469–10,982, n=9) → 3,444 ms (3,383–3,583, n=9)**, 3.11×, digest same;
  process CPU 10.6 s → 18.5 s.
- Verdict: kept.

### Fix 3: Decode the cached index on several cores with a fast date parser

- Commit: `66ff3a9`
- Hypothesis: 110 MB of JSON decoded one row at a time is ~1.9 s; parallel decode alone only reached 1.5 s with 7×
  the CPU, and the profile showed `os_unfair_lock` contention in `Calendar`/`TimeZone` construction inside the
  `.iso8601` date strategy.
- Change: rows are read in order and decoded with `ParallelMap` (8 threads: wall stopped improving above ~8, 0.65 s at
  8 and 12); the snapshot decoder uses `.fastISO8601`, a strict parser for `YYYY-MM-DDTHH:MM:SSZ` (years 1900–2199)
  that falls back to a real `.iso8601` decoder for every other spelling, including errors. `FastISO8601Tests` compare
  it with Foundation on ~700 boundary dates, 3,000 random instants and the declined spellings.
- Before → after: snapshot load **1,901 ms (1,855–1,919, n=15) → 645 ms (622–690, n=15)**, 2.95×; cache load
  **3,469 → 2,245 ms**, 1.55×; digest same.
- Verdict: kept.

### Fix 4: Read stored timestamps without ISO8601DateFormatter

- Commit: `cec2a0a`
- Hypothesis: metadata load (7k rows) and status history (24k rows) also build a calendar per row.
- Change: `FastISO8601.date(from:fallback:)` in `SQLiteSongUserMetadataStore` (rows keep their Foundation fallback);
  rows whose four JSON columns are the literal `[]` skip the decode.
- Before → after: metadata load **498 ms → 10.2 ms** (49×); all status history (Analytics) **1,609 ms
  (1,540–11,034) → 15.5 ms (14.8–16.2)** (104×); one song's history ×50 (5-row song) 24.6 → 6.5 ms; cache load
  2,256 → 1,751 ms. History digests same. (n=15 each.)
- Verdict: kept.

### Fix 5: Scan song folders in parallel and bound memory per folder

- Commit: `a7bd988` (ParallelMap's thread budget is part of this commit)
- Hypothesis: the full scan is I/O-syscall bound per folder (`sample`: `openat`, `read`, `faccessat` dominate), the
  folders are independent, and the loop has no autorelease pool (RSS 2.5 GB).
- Change: root entries are classified first (one stat each), folders are scanned in batches on up to 8 threads and merged
  back in directory order; cancellation is checked between batches; a scanner with a race hook installed (the
  swap-race tests) keeps the serial walk. `ParallelScanEquivalenceTests` compare a 150-folder archive with links, loose
  files and missing projects against the serial result; the swap-race and symlink-safety suites still pass. Tuning,
  measured: sys time 12.5 s serial, 70 s at 12–20 threads; wall 7.4 s at 4 threads, 5.9 s at 6, 5.3 s at 8.
- Before → after: scan **38,051 ms (37,582–42,901, n=6) → 5,757 ms (5,691–5,948, n=6)**, 6.6×, digest same; peak RSS
  2.5 GB → 0.7–1.0 GB; process CPU 29 s → 42 s (kernel time under contention).
- Verdict: kept. The CPU increase is the price of the wall time.

### Fix 6: Keep the intelligence pass and the recent-first sort off the launch hot path

- Commit: `14f0c01`
- Hypothesis: `sample` of the main thread during launch showed `scheduleIntelligenceRefresh` (collaborator suggestions,
  duplicate hints, missing audio) running on the main actor for ~400 ms, folding every collaborator name once per song,
  and `recentCPRActivity` sorting `(Song, Date)` tuples (copying and retaining every song's arrays on each move).
- Change: the three pure computations run in a cancellable utility task and only the results are applied on the main
  actor (same dismissal filtering); collaborator tokens are computed once per collaborator; recent-first shelves sort
  `(index, date)` pairs. `ArchiveBrowseSortEquivalenceTests` compare both with the old formulations.
- Before → after: recent sort **123.3 ms (114.6–129.6, n=21) → 29.8 ms (26.4–33.3)** (4.1×); intelligence pass
  **427 → 137 ms** (3.1×, and no longer on the main thread); launch main-thread CPU 3,038 → 1,884 ms; time lost to
  stalls 3,181 → 1,962 ms (n=3).
- Verdict: kept.

### Fix 7: Compare the 10,000-song catalog on several threads before republishing

- Commit: `97ecf1d`
- Hypothesis: when a rescan finds nothing new, `songs.willSet`, `ArchiveBoardProjectionCache.refresh` and
  `rebuildProjectVaultCatalog` each deep-compare 10,000 songs on the main thread (~150 ms each under `sample`).
- Change: `Array.equalsConcurrently` (same answer as `==`, same-storage shortcut, early stop on a mismatch) at those
  sites. `ParallelEqualityTests` check equal, equal-with-shared-storage, a mismatch at 7 positions and small arrays.
- Before → after (n=3): launch main-thread CPU 1,922 → 1,604 ms; worst stall 1,160 → 826 ms; open board
  **395 → 223 ms**; apply an unchanged scan result (board) 952 → 760 ms.
- Verdict: kept.

### Fix 8: Sort board columns by (index, date) pairs

- Commit: `cf089ac`
- Hypothesis: `ArchiveBoardProjection.columns` has the same tuple-sort problem.
- Change: sort `(index, date)` pairs, gather once. `ArchiveBoardProjectionTests` (newest CPR, ties by title) pass.
- Before → after: board projection **29.2 ms (23.2–33.1, n=21) → 20.8 ms (16.7–24.8)**, 1.4×, digest same. Opening the
  board did not change (340 → 340 ms): the layout, not the projection, dominates it.
- Verdict: kept, small.

### Fix 9: Skip per-song path canonicalization when no project is archived

- Commit: `783e8ad`
- Hypothesis: sampling `applyCatalogScanUpdate` put 800 of 1,500 samples in `ArchiveVaultObservation.projectCatalog` →
  `vaultCanonicalPath`, which resolves symlinks on disk for each of 10,000 folders even with no archived project.
- Change: with no archived destination or source path, the baseline songs are used as they are.
- Before → after: apply an unchanged scan result on the main actor **738 → 439 ms (board), 797 → 488 ms (list)**; worst
  launch stall 790 → 495 ms; launch main-thread CPU 1,511 → 1,210 ms (n=3).
- Verdict: kept. (A related guard in `snapshot(for:)`, which every card body calls, measured no difference — open
  board 318 vs 313 ms, detail and list unchanged over 4 alternating rounds — and was **not committed**.)

### Fix 10: Count quiet songs without sorting copies of every song

- Commit: `7603056`
- Change: `quietSongs` sorts `(index, date)` pairs; the Analytics overview uses a plain `quietSongCount`.
- Before → after: analytics snapshot **103.4 → 34.4 ms** (3.0×, digest same); open Analytics 362 → 205 ms. (The big step
  for Analytics, 3,661 → 360 ms, is Fix 4.)
- Verdict: kept.

### Fix 11: Index and match search on several cores for large catalogs; keep normalization serial

- Commits: `7f65cc5`, then `a5c839d` (the correction)
- Hypothesis: immediate search scores every song one at a time (`matchDetails`, fuzzy edit distance dominate).
- Change: `MusicSearchIndex.searchResults` maps the entries with `ParallelMap`; `sync` compares with
  `equalsConcurrently`. The first version also built the index (field normalization) in parallel; the micro benchmark
  showed that made it **slower** (318 → 374 ms with 9× the CPU, because every field is folded with the current locale
  and the threads contend on Foundation's locale cache), so `a5c839d` keeps normalization serial and parallelizes only
  the reuse decisions. `MusicSearchParallelismTests` compare a 1,500-song index with a serial reference and a synced
  index with a fresh one.
- Before → after: per query **246 / 201 / 259 / 254 / 192 ms → 36 / 30 / 37 / 36 / 28 ms** (6.6–7.1×, digests incl. scores
  and summaries same, n=15); index build 318 → 318 ms (after `a5c839d`); immediate search with layout, board old
  343 → 130 ms, recent 343 → 132, absent 287 → 118; list old 307 → 93, recent 316 → 97, absent 233 → 72.
- Verdict: kept.

### Fix 12: Encode the cached index rows on several cores

- Commit: `0094756`
- Change: `SQLiteArchiveIndexStore.save` encodes songs with `ParallelMap`; the stored rows are byte-identical to the serial
  encoding (`testLargeCatalogSavesTheSerialEncodingInOrderAndRoundTrips`).
- Before → after: save of an unchanged catalog **1,250 ms (1,225–1,271, n=15) → 345 ms (328–360)**, 3.6×. It runs after every
  scan and every metadata edit.
- Verdict: kept.

### Fix 13: Size scan batches by how long they take

- Commit: `1c7b427`
- Why: a fixed 128-folder batch is prompt to cancel on a local disk (~80 ms) but can take seconds on a network volume; a
  fixed 32 cost ~9 % scan time. Batches now start at 32 and scale toward ~150 ms (32–256).
- Before → after: scan 6,740 ms (5,800–7,889, n=9) → 6,596 ms (5,734–9,118): no change, which is the point.
- Verdict: kept.

### Fix 14: Reuse unchanged board columns and compare changed ones in parallel

- Commit: `92a8ae6`
- Hypothesis: moving one card on the board spends ~65 % of its main-thread samples in SwiftUI's repeated deep equality
  checks of whole columns (`ArchiveBoardColumn`, `ArchiveBoardColumnRenderKey`, `ArchiveBoardSongsView`).
- Change: `ArchiveBoardProjectionCache.refresh` keeps the previous column value when the new one is equal (later
  comparisons then find the same storage), `ArchiveBoardColumn.==` and `ArchiveBoardSongsView.==` use
  `equalsConcurrently`.
- Before → after (the parent against this commit, n=3): move a card, board, old song **185 → 169 ms**, recent
  192 → 171 ms; list unchanged (189 → 196, 108 → 107). What is left is SwiftUI re-diffing the 7,000-card lanes.
- Verdict: kept, small.

### Tried and reverted, or found not to help

- Per-card `snapshot(for:)` guard (Fix 9's neighbour): no measurable change, never committed.
- Parallel search-index build: slower, replaced in `a5c839d` (above).
- Fixed 32-folder scan batches: ~9 % slower than 128, replaced by Fix 13.
- A first `ParallelMap` split work into `threads × 4` fixed chunks, which let `concurrentPerform` start far more threads
  than the budget; it made the kernel time during the scan balloon (sys 12 s → 70 s). It was rewritten with a thread
  budget and dynamic claiming before `a7bd988`, so no committed state has the bug.

## Cumulative result

`script/performance/ab.sh` on original (`base`) against the branch, same session, medians (min–max), n=3 launches,
15 headless samples:

| Scenario (10k) | Original | Now | Change |
| --- | --- | --- | --- |
| Cached songs visible after launch | 16.83 s (16.77–16.91) | **2.59 s** (2.54–2.61) | 6.5× |
| Launch rescan finished | 48.0 s (45.1–48.4) | **8.77 s** (8.51–9.16) | 5.5× |
| Cache load, headless (digest same) | 15.54 s (15.36–16.26) | **1.80 s** (1.73–1.82) | 8.6× |
| Snapshot decode (digest same) | 1.89 s | **0.65 s** | 2.9× |
| Metadata load | 477 ms | **9.6 ms** | 49× |
| Full scan, headless (digest same) | 42.2 s (41.8–43.6) | **5.72 s** (5.41–6.77) | 7.4× |
| Cache save | 1.25 s | **0.34 s** | 3.7× |
| Worst main-thread stall during launch | 1,647 ms | **460 ms** | 3.6× |
| Time lost to stalls > 50 ms | 3,318 ms | **1,089 ms** | 3.0× |
| Main-thread CPU during launch | 3,314 ms | **967 ms** | 3.4× |
| Footprint after launch | 1,458 MiB | **690 MiB** | 2.1× |
| Open Analytics | 3,362 ms | **163 ms** | 21× |
| All status history | 1,537 ms | **15.3 ms** | 101× |
| Apply an unchanged scan result (board / list) | 825 / 866 ms | **393 / 455 ms** | 2.1 / 1.9× |
| Immediate search, old material (board / list) | 317 / 298 ms | **106 / 78 ms** | 3.0 / 3.8× |
| Search, absent query (board / list) | 269 / 222 ms | **95 / 61 ms** | 2.8 / 3.6× |
| Sort shelf "recent bounce" (board / list) | 287 / 157 ms | **94 / 54 ms** | 3.1 / 2.9× |
| Open board / list | 365 / 59 ms | **196 / 56 ms** | 1.9 / 1.1× |
| Move a card, board / list (old song) | 281 / 289 ms | **142 / 183 ms** | 2.0 / 1.6× |
| Recent-first sort / board projection / intelligence pass | 103 / 22 / 413 ms | **24 / 16 / 127 ms** | 4.3 / 1.4 / 3.3× |
| Real app: first window | 2.5–2.9 s | **1.4–1.5 s** | 1.8× |
| Real app: process quiet after launch | 20–42 s | **10.5–12.6 s** | 2–4× |
| Real app: peak RSS | 1.45–2.23 GB | **0.93–0.95 GB** | 2× |
| Process CPU, launch (in-process) | 53.9 s | 64.0 s | **+19 %** |
| Process CPU, launch (real app) | 30–55 s | 66–67 s | **+20–120 %** |
| Wheel scroll (top / oldest songs), open a song, tool screens | unchanged | unchanged | — |

On **1k** (3 alternating launches): cached songs 1.92 → 0.52 s, rescan finished 3.37 → 0.98 s, cache load
1,521 → 185 ms, full scan 2,747 → 516 ms, Analytics 397 → 68 ms, search 68 → 57 ms (board) and 35 → 22 ms (list),
stalled time 830 → 590 ms; nothing slower beyond noise.

The real-app numbers are single launches (3 each) through `script/bakeoff/app.sh` and `window-probe`; the "quiet"
time of the original varies 20–42 s because its one-thread scan waits on disk latency (its CPU curve is ~2 cores for
the cache load and ~1 for the scan), the in-process timeline above is the steadier comparison.

## Not done

- **Opening/updating the board is SwiftUI-bound (~200–350 ms for 10,000 cards, ~170 ms per card move).** After the fixes
  above the remaining time is `LazyVStack` placement and `ForEach` identity diffing of ~7,000-card lanes plus one
  `GeometryReader` preference per card (`ArchiveBoardCardFramesKey`, used only for drop landing). Fixing it means
  windowing the lanes or replacing that preference, which touches the UI design contract and drag-and-drop; I estimate
  100–150 ms per open/move.
- **Scan syscalls.** About 15 syscalls per audio file: `NoFollowPath.openParent` does `dup` + `openat(dir)` + `close`
  for every file, and the WAV header read is `read(12)` + 3× `lseek`+`read(8)` + `read(16)`. Caching one pinned directory
  descriptor per song and reading the header with one `pread` (falling back to today's code when a chunk lies past the
  buffer) would cut roughly 15–25 % of scan CPU and the kernel contention that makes launch CPU +17 %. I did not do it:
  the first is path-safety code ("no weaker safety checks") and the second needs an equivalence test over malformed
  WAVs.
- **Re-ranking every cached song at every launch** (~11 s of CPU, 1.1 s of wall on 12 threads). It exists so a better
  detector can replace stale cached roles; skipping it needs a detector-version stamp that cannot go stale, which I did
  not find a safe form for.
- **Output Inbox history at tens of thousands of rows.** Measured, not changed: 2,000 entries list in 11 ms / refresh in
  17 ms; 20,000 entries 115 / 192 ms off the main thread (JSON decode ~60 %, one `stat` per row ~35 %). A parallel
  availability pass would save ~60 ms at 20,000 rows; realistic inboxes are far smaller.
- **Applying a scan result on the main actor** still takes 390–460 ms (dictionary builds over 10,000 songs, effective-CPR
  lookups, browse recompute). It could move off the main actor, but the metadata merge must then be re-validated against
  edits made in between.
- **Startup before the window (1.3–1.5 s)** is mostly the system: `NSWritingToolsCoordinator` loads a framework while the
  main menu is built (~200 ms), window restoration, and `SMAppService.status` (~40 ms) in `AppComposition`.
- 1k and 10k only; I did not generate a 50k archive.

## Risks

- **More cores busy for a shorter time.** The launch now keeps up to 8–12 threads busy for ~10 s. Wall time fell
  5–8×, but process CPU seconds rose 17 % (in-process) to ~2× (real app, against a one-core original), mostly kernel time
  contending while many threads open files. On a laptop that is fan and battery for those seconds; the budgets
  (`ParallelMap.defaultMaximumThreads` = 8, normalization 12, scan 8) were tuned on a loaded 20-core Mac, and a machine
  with fewer cores simply runs fewer threads.
- **Concurrency correctness.** Every parallel site runs pure per-element work. Each has an equivalence test against the
  serial formulation, and the harness digests match, but any future closure passed to `ParallelMap` must stay free of
  unsynchronized shared state (its header says so). Swift 6 strict concurrency and `-warnings-as-errors` build clean.
- **Scan cancellation** is checked between batches (32–256 folders, sized to ~150 ms) instead of per folder, so Esc can
  take up to about one batch longer to stop a scan on very slow storage than before.
- **`FastISO8601`** accepts only `YYYY-MM-DDTHH:MM:SSZ` in 1900–2199; everything else goes to Foundation unchanged. The
  stored text is unchanged, so old and new builds read each other's databases.
- **Intelligence results arrive one scheduling hop later** (computed off the main actor); the tests that read them poll
  with deadlines, and a refresh superseded by a newer one is cancelled as before.
- **Interactions were measured through hosted views, not on screen.** Layout, display and `CATransaction.flush()` are
  included; compositor and input latency are not, and I could not take screenshots or drive the real window.
- **Process and verification.** `ModuleBoundarySourceTests` (Core may not import `Dispatch`) failed in the first version of
  the helper files; I folded the one-line fix into the commits that introduced them with a `git filter-branch` over my
  own commits so that no commit violates it. Each commit was checked with the test suites for the code it touched (and
  built in the A/B setup); the full `./script/ci.sh` was run on `fd4a2be` (the last code change; the commits after it only edit this report) and again on the final commit: exit 0, 779 XCTest cases
  (2 skipped, 0 failures), 93 Swift Testing cases, the CLI, release-engineering and public-tree gates, no compiler
  warnings (every target builds with `-warnings-as-errors`). Four `SystemAudioCapturePermissionProbeTests` /
  `SystemAudioTapInputLayoutTests` cases are timing-sensitive (10 ms fake-tap ticks) and fail in the agent shell
  (utility QoS, timer coalescing) with the **original** `Sources/` and `Tests/` as well; the same suites pass from
  Terminal.app, which is where the gate that counts was run. `./script/e2e_user_smoke.sh` was not run (release gate, and it
  needs UI automation this shell does not have).

## Changes on merge (2026-10-20)

This report comes from the October 2026 performance bake-off, where this branch ranked first. Before the
merge, four review points were checked and three were changed:

- **Folder workers per volume.** The scan used 8 workers on every disk. `ScanWorkerBudget.volumeLimit` now
  caps them at 2 on network volumes and 4 on other external volumes (Foundation cannot tell a spinning disk
  from an SSD), and keeps 8 on internal volumes. Not yet measured on the real archive disk (the WD was not
  connected); run `script/benchmark_scan_workers.sh <archive-root>` there before release. The same sweep on
  the Studio's internal SSD, 10k synthetic songs, 2 interleaved runs: 1 worker 31.4 s, 2: 16.8 s, 4: 9.2 s,
  8: 6.3 s (medians).
- **Background budget.** A rescan behind cached songs that are already on screen uses 4 workers; a scan
  the user starts and a first scan (empty board) keep 8. The first version also ran it at utility
  priority and used the small budget for first scans: the referee measured the cached-launch ready time
  at 12.8 s against 8.3 s and the first scan at 10.0 s against 7.4 s, so both were reverted.
- **Sendable contracts.** The `ParallelMap` transform and the search `include` filter are `@Sendable` and the
  elements `Sendable`; the job box stays `@unchecked` only for its result slots.
- **Cancellation inside a batch: no change needed.** The review assumed workers never see cancellation. The
  calling thread takes part in every batch and its folder scan throws at the next folder; `ParallelMap` then
  stops every thread before its next folder. `ScanWorkerBudgetTests.testCancellationStopsInsideABatch` now
  guards that a cancelled scan stops within about one folder per thread.
