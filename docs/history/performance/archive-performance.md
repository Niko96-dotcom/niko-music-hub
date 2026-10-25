# Archive performance investigation — 2026-09-05

The continued investigation retained improvements in four workflows: archive search,
preview ranking/scanning, board projection, and song metadata loading. It stopped after
the remaining candidates lacked a demonstrated low-risk benefit. This does not claim
that the entire repository is optimally fast on every input or machine.

## Changes and evidence

- **Search:** reject a song at the first failed required token; reuse normalized fields
  within that one song's match; classify folded ASCII bytes without Unicode property
  lookups; use byte subsequence matching only where Character equivalence is guaranteed.
  Foundation locale-sensitive folding and the complete Unicode/grapheme fallback remain.
  No normalized data survives a query or metadata edit.
- **Preview ranking:** compile fixed word-boundary regexes once; check tiers in descending
  order; parse production maturity, version and title-match facts once per candidate;
  pre-tokenize fixed negative labels. All scoring, reason order and tie-break criteria remain.
  The initial implementation repeatedly compiled regexes and reparsed names during sorting.
- **Board:** derive each song's effective CPR date once before sorting. Manual selection,
  ignored versions, title tie-breaks, column order and stable ties remain unchanged.
- **Metadata loading:** reuse one ISO8601 formatter per `loadAll()` invocation instead of
  creating one per row. Parsing behavior, fallback, SQL, validation and transactions remain.

Only five production files changed. Existing unrelated edits/deletions were preserved.

A baseline macOS `sample` put 2,313 of 2,375 main-thread samples under the production
search method, with Unicode character properties, normalization and matching prominent.
The profile is local at `.build/performance-search/before-sample.txt`; its timing run was
excluded. Workflow measurements then identified repeated parsing/formatting and sort-key
calculation. Each implementation stage had a previously measured baseline and matching
output digests before proceeding.

## Final measurements

Apple M5 Pro, macOS 26.5.2 (25F84), Apple Swift 6.3.3, locale `de_DE`, timezone `Europe/Berlin`. SwiftPM release core plus `swiftc -O`
drivers; board and analytics use their actual production source files alongside the driver.
Search compares against the original pre-task matcher. Workflow baselines were captured
before modifying those workflows; search-only changes already existed but are not called
by that benchmark. The starting working tree included unrelated edits at HEAD
`87860fb810fadd571a7408ecae020dda160c90b2`.

Two fresh processes per version ran in **before → after → after → before** order.
Each recorded first-use timing separately, performed two warmup rounds, then seven
measured rounds. Tables show pooled medians of 14 samples and full minimum–maximum ranges,
in milliseconds. Search rotates query order. No builds, tests or profiler ran concurrently
with the reported measurements; external system load and CPU frequency were not controlled.

### Search: 1,000 songs

Generated metadata has four CPR versions, six previews, aliases, collaborator names and
notes per song, plus occasional warnings. Inputs include accented titles, fuzzy queries,
multiple fields and an explicit absent-query control. All paths are in-memory identifiers.

| Query | Before median (range) | After median (range) | Time reduction |
|---|---:|---:|---:|
| `neon` | 59.73 (58.10–62.13) | 33.41 (32.49–35.99) | 44.1% |
| `neon hook` | 148.02 (145.62–154.76) | 52.31 (50.19–57.64) | 64.7% |
| `maria final` | 169.12 (165.77–172.91) | 60.02 (58.95–64.15) | 64.5% |
| `gravity v3 mix` | 152.36 (148.80–158.37) | 59.19 (54.82–63.80) | 61.2% |
| `noen hook` | 149.40 (146.32–181.22) | 54.46 (52.33–56.92) | 63.5% |
| `blumchen` | 92.22 (90.35–102.94) | 41.75 (40.15–46.37) | 54.7% |
| `zzzz absent` | 206.09 (200.25–213.73) | 46.05 (44.57–48.93) | 77.7% |
| `hook neon` | 145.79 (143.44–152.19) | 47.19 (44.30–50.16) | 67.6% |
| `blumchen maria` | 169.09 (165.82–178.09) | 44.46 (42.91–48.08) | 73.7% |
| `silver lining` | 178.39 (174.24–186.87) | 65.13 (63.82–72.04) | 63.5% |
| `summer rain` | 159.04 (154.40–165.56) | 54.75 (51.51–59.65) | 65.6% |

A 200-song cross-check also improved: `neon hook` 28.83 → 9.11 ms,
`hook neon` 28.95 → 8.34 ms, and `blumchen maria` 33.34 → 7.86 ms.
Every query preserved ordered IDs, scores and match explanations at both sizes.

### Other archive workflows

The in-memory catalog has 1,000 songs, each with 24 CPR versions and 36 previews, varied
dates/statuses and some ignored CPRs. A separate crowded project has 1,200 previews.
The scan uses 50 disposable song folders, 200 CPR fixture files and 600 valid, short WAVs.
SQLite fixtures contain the complete generated catalog; setup and output verification
are excluded from operation timing. Scan/SQLite runs exercise warmed local filesystem caches.

| Workflow | Before median (range) | After median (range) | Time reduction |
|---|---:|---:|---:|
| `rank_36_previews` | 4.36 (3.79–5.06) | 0.63 (0.55–0.79) | 85.7% |
| `rank_1200_previews` | 892.85 (874.23–914.95) | 20.12 (18.39–27.60) | 97.7% |
| `sort_1000_recentBounce` | 6.71 (6.15–7.36) | 7.24 (6.44–7.84) | -7.8% |
| `sort_1000_recentCPR` | 5.77 (5.43–6.54) | 5.74 (5.42–7.09) | 0.6% |
| `sort_1000_titleAZ` | 6.00 (5.61–6.53) | 6.12 (5.70–6.48) | -2.1% |
| `board_1000` | 36.83 (35.23–39.32) | 5.69 (5.46–6.66) | 84.6% |
| `analytics_1000` | 18.31 (17.94–18.94) | 19.47 (18.96–19.99) | -6.3% |
| `sqlite_load_1000` | 286.05 (273.00–291.66) | 315.18 (289.79–347.50) | -10.2% |
| `sqlite_save_unchanged_1000` | 199.00 (191.57–204.99) | 212.39 (195.59–233.79) | -6.7% |
| `metadata_load_1000` | 67.35 (65.57–71.27) | 29.93 (27.37–31.72) | 55.6% |
| `scan_50_songs_600_previews` | 181.21 (171.01–204.20) | 112.37 (105.10–120.11) | 38.0% |

The large retained improvements exceed observed variability. Untouched controls moved
by up to about 10%: notably archive snapshot load was 286 → 315 ms in this sequence.
That is a measured slowdown in the harness, not an improvement; this run does not isolate
its cause. Different preceding workloads, CPU state and allocation warmup can affect it.
No archive snapshot codec or analytics code was changed. Small control shifts are not
claimed as optimization wins, and these numbers should not be treated as precise whole-app
startup or end-to-end UI latency predictions.

All 11 workflow output digests matched across all final runs: ranked IDs/scores/reasons,
board ordering, sorted lists, complete loaded metadata/snapshots, analytics projections,
and complete scanned songs with the temporary root canonicalized. FNV-1a is a convenient
regression signature, not cryptographic integrity proof. Actual Vault verification still
uses its existing SHA-256 checks.

### Memory and startup tradeoffs

- Search adds a temporary dictionary of visited original/normalized fields for **one song**.
  Storage grows with those visited fields and is released after that song is matched.
  The index remains a lightweight song-array assignment; there is no persistent search cache.
- Ranking retains a fixed set of compiled regexes and negative-label token sets after first use.
  Their exact retained heap size was not separately measured. Initialization is lazy; first-use
  timings are recorded in the raw report. This is not a whole-app startup benchmark.
- Ranking and board sorting keep temporary O(n) arrays of derived facts. They are discarded
  after each projection; metadata uses one invocation-local formatter, without shared mutable state.
- Workflow-process peak RSS measured **348.28–349.62 MiB before** and **269.17–272.64 MiB after**.
  This includes the large fixture catalog and all benchmark operations, not installed-app RSS.
  The harness drains an autorelease pool after each iteration on both sides. An exploratory
  driver that did not drain pools accumulated its own temporaries; its memory result was discarded.
  These figures do not establish the cause or resolution of historical app memory incidents.

## Remaining candidates and stopping decision

| Area | Evidence / decision |
|---|---|
| Latest-bounce sorting | Tried lazy filtering/mapping to remove intermediates. Median 6.57 → 6.77 ms, with no useful gain. Reverted completely; the source matches its starting bytes. |
| Other shelf sorts | Roughly 6–7 ms for the 1,000-song fixture. Existing sorting already derives activity dates once. No further measured low-risk win. |
| Analytics | Roughly 18–20 ms for 24,000 version dates; snapshot is generated when opened, rather than every render. A calendar-bucketing rewrite adds calendar/DST semantics risk for modest benefit; not implemented. |
| Archive snapshot persistence | Roughly 200–315 ms for the heavy catalog. Existing per-song rows and transactions avoid unnecessary disk rewrites. A serialized-song cache would retain more catalog data and add synchronization/invalidation complexity; no such change was justified here. |
| Vault hashing/verification | Extended disposable fixture: manifest build 80.7 ms, verification 64.7 ms for 800 files. Existing bounded 1 MiB streaming buffer and complete validation retained. No shortcuts to hashing or path checks. |
| Audio analysis | Synthetic 12-second WAV: BPM 0.05 ms, hook location 0.18 ms, key estimate 49.3 ms. Analysis is capped; BPM/key work runs off the main actor and results are cached. No DSP arithmetic, sampling or cancellation changes made. These timings do not validate estimate accuracy. |
| Waveform UI | Source inspection found sparse capped decoding, a 48-entry peak cache, in-flight deduplication and cancellation. No additional measured bottleneck; no new waveform claim. |
| Converter/downloader/stems/recorder | Reviewed orchestration and existing buffer/concurrency controls. Major compute is in selected media backends or hardware capture; changing quality, concurrency or borrowed-buffer handling without representative host evidence was not justified. Existing unrelated edits in these modules were preserved. |

The retained experiments improved useful workflows without new persistent catalog caches,
changed audio output, weakened validation or real-user-data operations. More aggressive
algorithms, backend tuning and remote-storage behavior remain outside what these fixture
measurements establish; they are not silently declared solved.

## Verification

- `./script/ci.sh` passed: **1,161 XCTest tests, 5 runtime skips, 0 failures**, plus
  **54 Swift Testing tests**. Existing host-only CoreAudio exclusions remain in effect.
- Deterministic recorder gate, malformed-AX probe self-test, core self-test, CLI fixture
  export, release validation and release/source-distribution shell regression gates passed.
- `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` passed: actual debug app bundle,
  isolated settings/data, fixture search and dry-run CPR opening, denied archive writes,
  unchanged archive assertion, recorder inbox flow, and AX-visible first-run content.
- Added regression coverage for Unicode normalization, ASCII/control characters,
  grapheme-boundary subsequences, 441 token conjunction pairs, metadata rebuild freshness,
  maturity precedence/boundaries, and manual/ignored/equal-date board sorting.
- Existing ranker, search, browse and SQLite tests passed. Final benchmark digests matched.
- `git diff --check` passed. Original tracked edits/deletions were compared byte-for-byte
  with the initial saved diff and remained identical; unrelated untracked files were not edited.

No commit, push, installation, deployment, publication or real-user-data change occurred.
The debug E2E is not a release approval, installed-app UAT, or real cloud/hardware recovery proof.

## Reproduce

From the repository root:

```bash
./script/benchmark_archive_search.sh 1000 > /tmp/nmh-search-1000.json
./script/benchmark_archive_search.sh 200 > /tmp/nmh-search-200.json
./script/benchmark_archive_workflows.sh > /tmp/nmh-workflows.json
./script/benchmark_archive_workflows.sh --extended > /tmp/nmh-extended.json
./script/ci.sh
NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh
```

The drivers are Swift tooling, not embedded product runtimes. They create only in-memory
identifiers or temporary fixtures, clean up their temporary data, and place binaries in
`.build/performance-search`. Generation, compilation and digest verification are outside
timed operations. Locale, calendar/timezone, OS, compiler and external load can change results.

This session retained exact baseline/final executables locally:

```bash
for version in before after after before; do
  .build/performance-search/final/search-$version 1000
  .build/performance-search/final/workflows-$version
done
```

For strict replication of the recorded ordering, finish all four search runs before the
four workflow runs. Preserve each JSON separately. Those executables are ignored build
artifacts; reconstruct an old source baseline in a separate checkout rather than resetting
this dirty working tree.

[Raw final samples, first-use timings, digests and source hashes](archive-performance-results.json)
include the extended reconnaissance. The [first-pass search report](archive-search.md)
and its raw data are historical, superseded by this combined comparison.
Local final gate logs are `.build/performance-search/final/ci.log` and `e2e.log`.

## Historical note (2026-09-19)

This 2026-09-05 report body is retained with a new cross-reference to newer bounded synthetic
evidence in [Commercial readiness performance evidence — 2026-09-19](commercial-readiness-2026-09-19.md)
with curated data in [commercial-readiness-2026-09-19.json](commercial-readiness-2026-09-19.json).
