# Archive search measurements — 2026-09-05

> Historical first pass. The continued investigation and final implementation are documented
> in [Archive performance investigation](archive-performance.md).

Search now stops evaluating a song at the first missing required query token.
It preserves token order, all-fields matching, fuzzy behavior, scores, result ordering,
and match explanations. There is no added persistent cache or index-build work.

## Investigation and scope

Inspected archive scanning, SQLite snapshot loading/saving, and browse/search projection.
The scanner already requests directory resource properties and observes cancellation;
the SQLite store already uses per-song rows to limit writes. Neither was changed without
measurements supporting a further optimization.

`ArchiveBrowserViewModel.recomputeBrowseResults()` rebuilds its lightweight index and
runs search on the main actor after a 200 ms typing debounce. `matchDetails` previously
used `compactMap` over every token, only rejecting an incomplete match afterward. Thus
it continued normalizing fields, checking subsequences and running edit-distance matching
after a song was already ineligible. The change replaces that with an early return.

A separate 3-second macOS `sample` of the baseline benchmark found 2,313 of 2,375
main-thread samples under `MusicSearchIndex.searchResults`; Unicode character properties,
string normalization, and matching occupied the hot path. The sampled timing run was
excluded from the reported comparison. Its raw profile remains locally at
`.build/performance-search/before-sample.txt`.

Persistent normalized-field caching was not implemented: the current browse workflow
rebuilds the index on each refresh, so this would require additional invalidation behavior
or add work to refreshes without active search. One small optimization was sufficient.

## Measurement method

Apple M5 Pro, macOS 26.5.2 (25F84), Apple Swift 6.3.3. Core compiled with SwiftPM
`-c release`; standalone driver with `swiftc -O`. Baseline is the existing working tree
at HEAD `87860fb810fadd571a7408ecae020dda160c90b2`, including unrelated edits.
Only `MusicSearchMatcher.matchDetails` differs between the measured binaries.

Deterministic in-memory catalogs of 1,000 and 200 songs: each has four CPR versions,
six preview filenames, aliases, a collaborator and notes; some have warnings. Includes
accented titles, title searches, collaborator/note combinations, version/mix queries,
typos, reversed token order, and an explicit no-match control. Paths are identifiers only;
no real archives or music files are read or written.

Each fresh process records the first search separately, performs two full warmup rounds,
then seven measured rounds with rotated query order. Catalog generation, result digesting,
and compilation are outside query timing. No result cache is present; OS/code/allocator
warmup still matters. The first exploratory baseline was materially slower than later
runs, so use the warmed alternating comparison below, not the exploratory numbers.

The 1,000-song comparison ran **before → after → after → before** with no concurrent
builds, tests or profiling. The table pools 14 samples per query/version. Machine load
was not controlled globally; small changes inside overlapping ranges are noise, not wins.
The 200-song cross-check used one before/after pair (seven samples each).

Every iteration validates a stable FNV-1a digest of ordered IDs, scores and match
explanations. Before/after digests and result counts match for all 11 queries at both
sizes. This supplements correctness tests; the digest is not a cryptographic proof.
Raw samples, first-use timings, counts and digests are in
[archive-search-results.json](archive-search-results.json).

## Results

Milliseconds, pooled median (minimum–maximum). Positive change means less elapsed time.

| Query | Before | After | Reduction |
|---|---:|---:|---:|
| `neon` | 56.66 (53.52–59.86) | 54.87 (53.39–60.50) | 3.2% |
| `neon hook` | 136.63 (131.71–142.01) | 133.55 (131.91–143.30) | 2.3% |
| `maria final` | 156.34 (149.94–162.40) | 152.82 (150.72–162.50) | 2.3% |
| `gravity v3 mix` | 137.79 (135.57–147.96) | 138.06 (135.44–148.45) | -0.2% |
| `noen hook` | 134.47 (132.07–143.45) | 135.20 (132.67–142.81) | -0.5% |
| `blumchen` | 85.61 (82.91–89.23) | 84.13 (83.13–91.25) | 1.7% |
| `zzzz absent` | 184.20 (182.13–197.46) | 93.23 (91.75–101.52) | 49.4% |
| `hook neon` | 137.30 (131.23–141.51) | 103.60 (101.68–108.19) | 24.5% |
| `blumchen maria` | 160.89 (152.41–194.41) | 89.91 (87.96–96.48) | 44.1% |
| `silver lining` | 169.40 (160.59–186.57) | 163.13 (159.72–174.21) | 3.7% |
| `summer rain` | 147.15 (141.84–155.05) | 131.65 (128.85–141.41) | 10.5% |

The clear selective-query improvements are `hook neon` (24.5%), `blumchen maria`
(44.1%), and `summer rain` (10.5%). The deliberately absent query improves 49.4%.
Single-word queries and multiword queries whose early tokens match every song do not
benefit structurally; their observed shifts of roughly −0.5% to +3.7% are not claimed
as improvements. Broad fuzzy matches are existing behavior and remain intact.

The 200-song cross-check: `hook neon` 27.68 → 21.40 ms; `blumchen maria`
32.28 → 18.65 ms; `summer rain` 30.01 → 27.03 ms. These correspond to roughly
6–14 ms saved, versus 15–71 ms saved in the larger catalog.

## Tradeoffs and limits

No persistent memory or startup cost is introduced. Process peak RSS was 21.41–21.75 MiB
before and 21.03–21.09 MiB after in the large alternating runs; this small process-wide
difference is not a claimed memory improvement. Index rebuild remained a trivial array
assignment (one noisy sub-0.003 ms observation per process); this is not a startup benchmark.
The temporary match-details array remains bounded by query token count.

Benefits depend on the position of a failing token: `hook neon` improves while `neon hook`
does not in this corpus. Token order is not changed because it controls explanation order.
Single-word queries and songs matching all tokens retain their existing work. No
unsuccessful implementation experiment was retained or needed reverting.

These are measurements of the production search operation with generated, representative
metadata, not real-library profiling or end-to-end keystroke-to-frame measurements.
The expected reduction in main-thread stalls follows from the verified call path; actual
UI frame latency, larger/heavier catalogs, storage scanning, and whole-app startup were
not timed. Background system load and locale can affect results.

## Reproduction

From the repository root, with Xcode available:

```bash
./script/benchmark_archive_search.sh 1000 > /tmp/nmh-search-1000.json
./script/benchmark_archive_search.sh 200 > /tmp/nmh-search-200.json
```

The script builds only the release core, links the same production search implementation,
and runs an in-memory fixture driver. It writes its binary beneath `.build/performance-search`.
For future comparisons, preserve that binary before editing, then rebuild and run the two
binaries alternately, keeping compilation/profiling outside measurement runs.

This session retained exact before/after executables locally, so it can be repeated without
changing the working tree:

```bash
.build/performance-search/archive-search-before 1000 > /tmp/nmh-before-1.json
.build/performance-search/archive-search-after 1000 > /tmp/nmh-after-1.json
.build/performance-search/archive-search-after 1000 > /tmp/nmh-after-2.json
.build/performance-search/archive-search-before 1000 > /tmp/nmh-before-2.json
```

Those binaries and the original matcher copy are ignored build artifacts, not portable
repository inputs. To reconstruct the old implementation later, use a separate checkout
of the recorded baseline and copy the benchmark script/driver there; do not reset a dirty
working tree. Compare ordered-output digests as well as timing samples.

## Verification

- `./script/ci.sh` passed: 1,156 XCTest tests (5 runtime skips, 0 failures),
  54 Swift Testing tests, deterministic recorder check, malformed-AX probe self-test,
  core self-test, CLI fixture export, release validation and shell regression gates.
  The script's existing host-only CoreAudio exclusions remain in effect.
- The new conjunction regression test covers 441 token pairs across all searchable
  metadata categories plus empty input, duplicate tokens, and first/middle/last misses.
  Existing search, fuzzy matching, explanation, browse and view-model tests also passed.
- `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` passed, including fixture search,
  dry-run CPR opening, denied archive writes, archive-unchanged validation, recorder
  inbox flow and AX-visible public first-run content. App settings/data were isolated.
- `git diff --check` passed. All pre-existing tracked edits/deletions were compared
  byte-for-byte with the initial saved diff and remained unchanged. Unrelated untracked
  files were not edited. No commit, push, installation, publication or real-data change.

Local gate logs are `.build/performance-search/ci.log` and
`.build/performance-search/e2e.log`. The app E2E used the repository's default debug
bundle; search timing used release core code. This is not release or installed-app UAT.
