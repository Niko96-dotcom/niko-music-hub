# Archive browse shelf reuse — 2026-09-26

Active searches now reuse the shelf-scoped search index without deriving the same shelf a second time. Both immediate browse refreshes and debounced background searches already prepare that index. Empty queries still derive, filter, and sort the live shelf; standalone projections still build their own index. No new persistent cache, changed ranking, library cap, or UI design change is introduced.

## Measurements

Baseline: `43877d4609fee6229c19fbce0be202fba4a2c754`. Candidate production change is limited to `ArchiveBrowseProjection.swift`; the raw report records source, driver, and binary SHA-256 hashes. The same release core object files and benchmark driver were linked with the baseline and candidate projection sources.

Host: Mac17,8, 18 CPUs, 48 GiB RAM, macOS 26.5.2 (25F84), Apple Swift 6.3.3, arm64; `swiftc -O`. Two fresh processes per version in **before → after → after → before** order at each scale. Each workflow records a first invocation, two warmups, then seven measured rounds: tables pool 14 samples per version. No builds, tests, or profiling ran concurrently with these timed trials; unrelated system load was not controlled.

Generated in-memory catalogs have four project versions and six previews per song, varied collaborator/status/hidden metadata, and fixed historical dates safely outside the Quiet Songs threshold. The `neon` query returns 100 and 1,000 visible songs from the 1,000- and 10,000-song catalogs (hidden songs excluded). Quiet Songs exercises the unfinished subset; it does not test a moving 30-day boundary. No real archive files are accessed.

The timed operation includes shelf derivation, warm index synchronization, and the production browse projection. Index construction is recorded separately; full ordered Song values, summaries, skipped matches, and searching state are digested outside timing. Empty query is a separate shelf/filter/sort control. This is CPU browse work, not end-to-end UI latency.

### 1,000 songs

| Workflow | Before median (range), ms | After median (range), ms | Reduction |
|---|---:|---:|---:|
| By Collaborator | 5.50 (5.26–5.85) | 4.31 (4.07–4.42) | 21.6% |
| Recent Project Activity | 17.50 (16.79–18.91) | 13.40 (12.75–15.05) | 23.4% |
| Recently Bounced | 17.99 (17.38–19.59) | 13.66 (13.19–13.91) | 24.1% |
| Quiet Songs | 14.29 (13.57–15.08) | 11.10 (10.68–11.47) | 22.3% |
| All Songs (control) | 9.93 (9.51–10.69) | 9.80 (9.40–10.05) | 1.3% |
| Empty query (control) | 3.68 (3.36–3.91) | 3.75 (3.41–4.22) | -2.0% |

### 10,000 songs

| Workflow | Before median (range), ms | After median (range), ms | Reduction |
|---|---:|---:|---:|
| By Collaborator | 68.16 (66.36–80.74) | 50.60 (49.32–52.51) | 25.8% |
| Recent Project Activity | 179.00 (172.49–181.72) | 139.49 (136.82–186.10) | 22.1% |
| Recently Bounced | 180.58 (174.62–205.37) | 145.51 (137.76–180.84) | 19.4% |
| Quiet Songs | 160.84 (155.59–170.49) | 124.35 (121.55–136.63) | 22.7% |
| All Songs (control) | 103.02 (100.80–123.67) | 100.84 (99.04–102.73) | 2.1% |
| Empty query (control) | 41.24 (39.22–48.53) | 41.00 (38.12–48.29) | 0.6% |

Each of the four activity/collaborator shelves improved its median in both fresh candidate processes at both sizes. The 10,000-song Recent Project Activity and Recently Bounced full ranges overlap because of slow candidate outliers; those samples are retained, not discarded. All Songs and empty-query controls moved only about 0–2%; those small shifts are not claimed as wins. All 12 workflow/scale output digests and result counts match across all four trials. FNV-1a is a regression signature, not a cryptographic integrity guarantee.

## Remaining limits

The existing 10,000-song board/list fixture at the baseline recorded median search-to-layout latency of 360/307 ms including the 200 ms debounce, with median maximum main-loop gaps of 93/40 ms. That fixture uses All Songs and is background context, not a before/after measurement for these shelf changes. This change does not establish smooth frame pacing, faster scanning, whole-app startup, installed-app behavior, or performance on real libraries. Archive Browser remains a broad feature; this is a measured optimization, not a module decomposition.

## Validation

- Full-result parity across every shelf, hidden modes, combined filters, matching/missing queries, and a missing collaborator; clearing search with a stale supplied index. Existing freshness/cancellation tests retained.
- Initial focused run: 476 of 477 tests passed; the existing user-flow test hit checkout timestamps in ranking fixtures. Running the repository fixture generator restored the required equal timestamps; the 22-test browse/user-flow rerun passed.
- `./script/ci.sh` passed in the isolated candidate checkout: 2,286 XCTest cases, 8 skips, 0 failures; 66 Swift Testing cases; deterministic recorder, UI-probe, core/CLI, release and source-distribution checks passed.
- `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` passed with isolated settings, fixture archive unchanged, dry-run project opening, recorder/inbox flow and AX-visible first-run UI.
- The new benchmark wrapper ran successfully at 1,000 songs; its output digests match the candidate trials. Shell syntax, result JSON, source hashes, document link and `git diff --check` passed.
- Muse supplied the bounded diagnosis/implementation; Cursor Grok independently reviewed the frozen diff, tests, callers and measurement method and accepted with no material findings. The coordinator ran all checks and reviewed raw samples.
- All six files were integrated byte-for-byte into the unchanged baseline main checkout; the 22 focused browse/user-flow tests passed again there.
- This is source and isolated debug-runtime validation; no installed-app or published-release claim is made.

## Reproduce

```bash
./script/benchmark_archive_browse.sh 1000
./script/benchmark_archive_browse.sh 10000
./script/ci.sh
NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh
```

For A/B reproduction, compile this same driver against the baseline projection in an isolated checkout and against the candidate, preserve both binaries, then run them in the order above without concurrent builds/tests. Do not reset a working checkout to obtain the baseline.

[Raw samples, first-use/index initialization timings, counts, digests, and exact source hashes](archive-browse-2026-09-26-results.json).
