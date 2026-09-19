# Commercial readiness performance evidence — 2026-09-19

Bounded, synthetic-fixture evidence only. No personal paths, source logs, or real music data.

- Historical 2026-09-05 report bodies are retained with a new cross-reference to this evidence; this report does not rewrite their bodies.
- Compact curated evidence in `commercial-readiness-2026-09-19.json` retains medians plus key digests; full samples are not in the compact JSON.
- Statuses: Project Vault catalog index and output-inbox total-work are accepted as local evidence. Search integration (normalized per-index cache + incremental invalidation + lazy empty-query skip), UI fixture runtime, and scan/workflows runtime remain **candidate only until final review**, not accepted into main.

## Method, hardware dependence, and reproducibility

Evidence host (from frozen fixtures, sanitized — no hostname/paths): 18 CPUs, 51539607552 physical-memory bytes, macOS Version 26.5.2 (Build 25F84), `build_config: release`. All thresholds below are newly defined post-measurement local regression thresholds valid only on this host/config. They are not a universal SLA and not pre-existing acceptance.

Reproducible drivers for this package (fixture-relative; generation/compilation/digest verification outside timed sections; no concurrent builds/tests/profiling during timed runs). Curated keys are named in `commercial-readiness-2026-09-19.json`:

- Search (`search.1000.queries`, `search.10000.queries`; in-memory `MusicSearchIndex.searchResults` only; no music files read): `./script/benchmark_archive_search.sh` — deterministic 1000-song and 10000-song catalogs, 11 queries (`neon`, `neon hook`, `maria final`, `gravity v3 mix`, `noen hook`, `gluhwurm`, `zzzz absent`, `hook neon`, `gluhwurm maria`, `silver lining`, `summer rain`), 2 warmup rounds + 7 measured rounds, rotated query order, rebuild timed separately. No caps/discard: every song scored per query.
- Vault (`vault.isolated_primary.scales`, `vault.stable_id_semantic`; `tool: vault-recovery-reconciliation`, fixture-only under one UUID temp root removed afterwards; safe read-only/reconciliation only — never `recoverAtLaunch` copy faults, `LocalVaultTransferEngine`/`RestoreEngine` copies, or auto-retry copies): `./script/benchmark_vault_recovery.sh` — scales 100 / 1000 / 10000 records, 3 warmup + 7 measured rounds, release.
- UI (`ui_nshosting_fixture.workflows`; source method is synchronous main-thread mutation + `NSHostingView` layout + display + `CATransaction` flush in an actual `NSHostingWindow` fixture window owning its size; 10000 songs, 4 versions per song, 1440x900 points, `hosting_sizing_options: none`; measurement records layout application, not off-main compute): `./script/benchmark_archive_ui.sh` — 3 warmups + 15 measured iterations (search probes 3 warmups + 7 measured), 2 ms heartbeat. Not GPU presentation, input-to-photon, audio playback, or installed-app UAT.
- Scan (`scan_cli.results`; actual CLI synthetic): one-off fixture harness invoking `NikoMusicHubCLI export-index --roots <generated-root> --output <temporary-export.json>` — projects 100 / 1000 / 10000 with distinct files 200 / 2000 / 20000, JSON export bytes 250245 / 2511847 / 25217849.
- Inbox (`inbox_refreshAvailability_listItems.sizes`; `tool: output-inbox-refresh`; scope `refreshAvailability+listItems` total work only; steady state pending warmed to available; rounds measure load + stat + sort with save skipped): `./script/benchmark_output_inbox.sh` — items 100 / 1000 / 10000, 64-byte files, 5 measured rounds.

Frozen inputs/outputs curated in `commercial-readiness-2026-09-19.json`; originals retained locally in `.codex/performance-evidence/` (`search-1000.json`, `search-10000.json`, `search-before.json`, `search-10000-before.json`, `vault-after.json`, `vault-before-stable-ids.json`, `vault-after-stable-ids.json`, `vault-scaling.json`, `ui-after.json`, `ui-10000-before.json`, `scan-before.json`, `inbox-before.txt`, `benchmark-corrected.json`, `workflows-before.json`). Historical 2026-09-05 driver commands remain documented in their own reports and did not reproduce vault/inbox/UI for this package.

## Fixture sizes and distinct files

- Search: 1000 songs and 10000 songs; 11 queries each.
- Vault: records 100 / 1000 / 10000; distinct files 100 / 1000 / 10000; manifest entries 125 / 1250 / 12500; manifest total bytes 16000 / 160000 / 1600000; `file_bytes_cpr: 64`, `file_bytes_wav: 256`; transfer blob bytes 1215 / 1218 / 1221. Largest scale is 12.5k manifest files of tiny 64/256-byte payloads — not large-audio throughput or power-cut proof.
- UI: 10000 songs, `versions_per_song: 4`, 1440x900 fixture window.
- Scan CLI: 100→100/200 files, 1000→1000/2000 files, 10000→10000/20000 files.
- Inbox: rows/items 100 / 1000 / 10000, distinct files 100 / 1000 / 10000.
- No arbitrary user record caps are imposed: search scores every song per query; budgets are latency thresholds, not library-size limits.

## Measured before/after (medians plus key digests; full samples are not in the compact JSON)

### Search candidate vs baseline

Before baselines: `search-before.json` (1000 songs, `index_rebuild_ms: 0.000667`, peak 22413312 B) and `search-10000-before.json` (10000 songs, `index_rebuild_ms: 0.00075`, peak 125779968 B) — rebuild was a trivial array assignment.

| songs | query | before median | candidate median |
|---|---|---:|---:|
| 1000 | neon | 30.456 ms | 12.679 ms |
| 1000 | neon hook | 58.872 ms | 18.916 ms |
| 1000 | maria final | 55.927 ms | 15.254 ms |
| 1000 | gravity v3 mix | 52.022 ms | 12.208 ms |
| 1000 | noen hook | 59.859 ms | 19.149 ms |
| 1000 | gluhwurm | 48.806 ms | 10.675 ms |
| 1000 | zzzz absent | 55.637 ms | 13.552 ms |
| 1000 | hook neon | 50.210 ms | 13.417 ms |
| 1000 | gluhwurm maria | 51.336 ms | 11.301 ms |
| 1000 | silver lining | 51.764 ms | 13.084 ms |
| 1000 | summer rain | 51.024 ms | 12.810 ms |
| 10000 | neon | 318.704 ms | 126.357 ms |
| 10000 | neon hook | 611.880 ms | 192.744 ms |
| 10000 | maria final | 585.730 ms | 155.812 ms |
| 10000 | gravity v3 mix | 539.607 ms | 124.407 ms |
| 10000 | noen hook | 630.995 ms | 194.694 ms |
| 10000 | gluhwurm | 509.237 ms | 113.994 ms |
| 10000 | zzzz absent | 584.051 ms | 138.585 ms |
| 10000 | hook neon | 527.689 ms | 138.484 ms |
| 10000 | gluhwurm maria | 541.806 ms | 119.658 ms |
| 10000 | silver lining | 552.238 ms | 146.187 ms |
| 10000 | summer rain | 540.678 ms | 143.287 ms |

Candidate costs (cold-index): 1000-song `index_rebuild_ms: 41.632833`, invalidation `rebuild_ms: 38.624166`, peak 24002560 B; 10000-song `index_rebuild_ms: 409.423666`, invalidation `rebuild_ms: 394.523542`, peak 147193856 B. `unrebuilt_stable: true` in both. Candidate adds normalized per-index cache, incremental invalidation, and lazy empty-query skip. Candidate until final review; not in main.

Output equivalence: all 11 query digests match baseline at each size (e.g. 1000-song `d8216bdca13abc6d`, `7087e43f1eabbf07`, `ca3fcaccce52e14`, `456f1bef5eda3bb7`, `598a413195d255cb`, `99fb81b0ecb07257`, `cbf29ce484222325`, `e7ab5e76c1d080e7`, `3090e479e1cc6fd9`, `23e7f7eb2e92f8d7`, `9ddfae23f513fa23`; 10000-song `3afe8345c3a35a1`, `28361a338abaebbf`, `38bc1a1fe81d4370`, `8e56f3f5d4b3683f`, `cb14485c2b8c836f`, `eca951751cb66e03`, `cbf29ce484222325`, `cd5317a1ddbfdf3f`, `e8602718736c2081`, `24c963747851244f`, `2acf36c4b678ee73`). Curated JSON records `unrebuilt_stable: true` in both sizes plus before/after digests and rebuild timings.

### Vault / catalog (accepted index) — isolated timings primary

Original catalog digests differed due to random `existingUUID`. Stable-ID reruns give semantic digest match on `catalog_reconcile` at all 3 sizes: 100-record `b625c29c21c5303a`, 1000-record `f86c9621274658aa`, 10000-record `dab988e92d11883f` (before-stable equals after-stable). Stable-ID timing reruns were concurrent, so original isolated timings are primary (see caveats).

Isolated (primary): `vault-scaling.json` (before, peak 512229376 B) vs `vault-after.json` (after, peak 546471936 B):

- 100 records: manifest build 7.518→8.389 ms; verify 6.177→6.620 ms; transfer save 2.398→2.650 ms; load 1.291→1.341 ms; catalog reconcile 1.362→0.297 ms; catalog save 1.526→1.690 ms; load 1.177→1.209 ms; restore 3.315→4.644 ms.
- 1000 records: build 79.185→105.669 ms; verify 66.300→78.725 ms; save 26.113→27.032 ms; load 13.824→13.615 ms; catalog reconcile 127.892→3.220 ms; catalog save 16.195→19.089 ms; load 12.274→12.426 ms.
- 10000 records: build 814.198→838.824 ms; verify 684.111→694.281 ms; save 264.844→275.860 ms; load 160.044→166.439 ms; catalog reconcile 12630.358→38.365 ms; catalog save 165.004→173.652 ms; load 135.084→140.140 ms.

Correctness at each scale (both sides): `catalog_reviews` 50/500/5000, `corrupt_throws: true`, `missing_throws: true`, `recoverable_match: true`, `verified_ok: true`. Manifest digests `29ffac301f2fa1b7` / `5eb9a8b3208cea1d` / `275a5b1323e42af7` unchanged. Largest scale is 12.5k tiny files (see fixture section), not large-audio throughput.

Restore reconciliation uses 100 records at the smallest scale and 200 records at each larger scale. Its timings do not establish 10,000-record restore performance. This is a benchmark fixture limit; the product has no corresponding history cap.

### Inbox (detached IO, one-pass decode/stat)

`benchmark-corrected.json` `baseline_ms` / optimized fields (5 rounds, peak 66076672 B; curated `inbox_refreshAvailability_listItems.sizes`); digests exist only in `benchmark-corrected.json`. `inbox-before.txt` is a separate 4-iteration run and is not used for this pairing:

- 100 items (`207a01c202b1a02c`): baseline median 0.936 ms → optimized 0.608 ms.
- 1000 items (`adc9c769df177e1d`): 10.486 ms → 6.524 ms.
- 10000 items (`ec40eff28f9aebe7`): 98.247 ms → 61.958 ms.

Scope is `refreshAvailability+listItems` total work only; main-thread responsiveness is covered by `OutputInboxRefreshTests`, not claimed here. Digest preserved per size.

### Scan CLI synthetic (1000/10000 actual)

These timings came from a one-off fixture harness invoking the release `NikoMusicHubCLI export-index --roots <generated-root> --output <temporary-export.json>` command three times per scale. `benchmark_archive_workflows.sh` uses a different scan fixture and does not reproduce this 100/1000/10000-project measurement.

`scan-before.json` (`scan_and_json_export_seconds`):

- 100 projects / 200 files / 250245 B: 0.413608 s (iter0) / 0.051510 s / 0.047977 s.
- 1000 / 2000 / 2511847 B: 0.392841 s / 0.410666 s / 0.395344 s.
- 10000 / 20000 / 25217849 B: 3.965298 s / 3.992205 s / 3.971262 s.

Warmed filesystem caches; generation/verification outside timing excluded per driver.

### UI fixture 10k/4CPR (synchronous main-thread layout application)

`ui-10000-before.json` vs `ui-after.json` (medians; curated `ui_nshosting_fixture.workflows`):

- board_selection 36.689→31.150 ms; board_typing 4.300→3.088 ms; board_search_results_layout 281.800→152.441 ms on the main thread; board_status 38.464→30.433 ms; board_resize 16.151→13.226 ms.
- list_selection 73.443→73.642 ms (no change); list_typing 4.649→4.155 ms; list_search_results_layout 235.312→98.872 ms on the main thread; list_status 26.198→20.149 ms; list_scroll 28.724→25.526 ms (first 1466.268→1522.854 ms cold); list_resize 18.135→16.140 ms.
- board_debounced_search_latency 473.624→334.252 ms; list_debounced 445.419→305.984 ms — elapsed latency including wait, not off-main compute; debounce wait is not background execution.
- Main-loop gaps (limitation): board_maximum_main_runloop_gap 63.141→68.026 ms; list_maximum 37.101→39.363 ms. CPU work: board 61.442→65.822 ms; list 36.176→37.929 ms.

This measures synchronous main-thread `NSHostingView` layout application in a fixture window, not installed-app UAT, GPU presentation, or input-to-photon latency. Search-through-layout remains on the main thread. No 60 fps claim: 68/39 ms gaps exceed the 16.67 ms frame budget.

## Proposed local regression thresholds (newly defined post-measurement) vs aspirational targets

All thresholds below are newly defined post-measurement local regression thresholds valid only on the evidence host/config above. They are not pre-existing acceptance criteria and not independent qualification. No pass/fail badge is claimed until repeat validation; comparisons state whether the measured median is within the proposed budget.

Only traceable pre-existing guidance: search 1000-song typing guidance ~60 ms max with 10k off the keystroke path; vault 100-record reconcile/save/load well under 1 s with 1k/10k as background work and single-project verify in milliseconds as guidance. All other numbers are newly proposed with rationale/headroom.

- Typing fast path: proposed 1000-song per-query median ≤60 ms max (carries forward pre-existing guidance). Candidate 10.7–19.1 ms within proposed budget; baseline 30.5–59.9 ms within proposed budget at margin. 10000-song medians 114–195 ms candidate / 319–631 ms baseline exceed the typing fast-path budget if placed synchronously on keystroke; for 10k keep off keystroke per pre-existing guidance (debounced).
- Cold index (one-time, never per keystroke): proposed 1000-song rebuild ≤80 ms and 10000-song rebuild ≤600 ms as one-time cost, rationale ~2x headroom over measured 41.6 ms / 409.4 ms plus incremental invalidation 38.6 ms / 394.5 ms. Measured 41.6 ms / 409.4 ms within proposed budget as one-time cost; exceeds budget if used per keystroke (hence incremental invalidation + lazy empty-query skip in candidate).
- UI typing/layout (synchronous main-thread): proposed board_typing ≤8 ms and list_typing ≤8 ms p50, rationale ~2x headroom over measured ~3–4 ms. After 3.09/4.16 ms within proposed budget.
- UI selection (synchronous main-thread): proposed board_selection ≤50 ms and list_selection ≤100 ms p50, rationale headroom over measured 31.15/73.64 ms with list near margin. After 31.15/73.64 ms within proposed budget.
- Main-loop gaps (limitation): 16.67 ms 60 fps aspirational target. After board 68.03 ms / list 39.36 ms remain limitation, no 60 fps claim.
- Debounced search latency (elapsed including wait; layout itself remains synchronous main-thread per source method): proposed board ≤400 ms / list ≤350 ms p50, rationale headroom over measured after 334.25/305.98 ms with before 473.62/445.42 ms outside. After within proposed budget; before outside. Debounce wait is not off-main compute.
- Inbox total work: proposed 10000-row ≤80 ms p50, rationale ~30% headroom over optimized 61.96 ms. Optimized 61.96 ms within proposed budget; baseline 98.25 ms (`benchmark-corrected.json` `baseline_ms`) outside. Not a main-thread responsiveness claim.
- Vault 100-record launch (must not block first frame/input; pre-existing guidance well under 1 s): measured reconcile 0.297 ms, save 1.690 ms, load 1.209 ms, transfer save 2.650 ms, transfer load 1.341 ms, manifest build 8.389 ms, manifest verify 6.620 ms — all within guidance. Smallest measured verify is the 100-record / 125-entry manifest; no 4-file verify was run and none is claimed.
- Vault library-scale (background maintenance, off typing/scroll): 1000/10000-record catalog/transfer work has no interaction budget per pre-existing guidance; must stay off typing/scroll path. Measured up to ~839 ms build / 694 ms verify / 276 ms save at 10000: background-only by design.
- Scan batch: 10000-project CLI ~4 s: background-only; no interaction budget.

Aspirational (explicitly not acceptance): universal cross-machine SLA, 60 fps landing/search-result animation, large-audio (multi-MB/GB) throughput, power-cut recovery proof, installed-app UAT, whole-app startup/RSS. No record caps are set: thresholds are per-operation latencies; every song is scored, no discard.

## Memory and cold-index costs

- Search: peak RSS 22.4→24.0 MB (1000 songs), 125.8→147.2 MB (10000 songs); rebuild 0.0007→41.6 ms and 0.0008→409.4 ms respectively. Cost is one-time per index + incremental invalidation (38.6/394.5 ms fresh rebuild), not per query.
- Vault: peak RSS 512.2 MB (scaling before) / 546.5 MB (after) / 531.8–549.0 MB (stable-ID reruns); includes full fixture catalogs and all operations, not installed-app RSS. First-iteration colds (e.g. restore first 362–957 ms vs medians ~3–5 ms; 10000 manifest build first ~848 ms) recorded separately in fixtures.
- UI: fixture-process only; recorded `first_ms` colds (e.g. list_scroll first 1466–1523 ms vs medians ~25–29 ms) are already-mounted-window first operations, not app startup.
- Inbox: 66.1 MB peak for refresh driver; includes fixture rows, not app RSS.
- Workflows baseline (`workflows-before.json` via `benchmark_archive_workflows.sh`, 1000 songs, peak 305119232 B; curated `workflows_context`): rank_36 2.029 ms, rank_1200 66.535 ms, sorts ~5–7 ms, board_1000 4.928 ms, analytics 16.467 ms, sqlite_load 256.460 ms, sqlite_save_unchanged 177.876 ms, metadata_load 23.762 ms, scan_50 104.925 ms, vault_manifest_800 56.896 ms, vault_verify 48.192 ms, bpm 0.049 ms, key 40.605 ms, hook 0.144 ms — context only.

## Caveats and what is not proven

- Stable-ID vault timing reruns were concurrent; original isolated timings (`vault-scaling.json` vs `vault-after.json`) are primary. Stable-ID reruns establish semantic digest match only.
- Search integration, UI fixture runtime, and scan/workflows runtime remain candidate; final review pending. Do not integrate or claim main-line wins. Catalog index and inbox total-work are the accepted local evidence in this package.
- Main-loop gaps ~68 ms board / ~39 ms list remain; synchronous main-thread search-result layout still causes noticeable pauses at 10k. No 60 fps claim.
- Vault largest scale is file-count stress with tiny payloads; not large-audio throughput, disk-full, or power-cut recovery. Smallest measured verify is 100-record / 125-entry manifest.
- Scan is synthetic CLI with warmed caches; not real-library profiling or end-to-end keystroke-to-frame.
- UI fixture applies synchronous main-thread layout in `NSHostingWindow` but is not installed-app UAT, GPU frame pacing, or whole-app startup/memory.
- External load/CPU frequency not controlled; small shifts inside overlapping ranges are noise. First-use timings kept separate; pooled medians reported.
- Privacy: synthetic evidence only. Curated JSON omits hostnames, absolute/temp paths, and source logs; paths replaced with fixture-relative descriptors. Curated JSON retains medians plus key digests; full samples are not in the compact JSON.

## Curated evidence

Repo-relative: [commercial-readiness-2026-09-19.json](commercial-readiness-2026-09-19.json). Curated keys: `search.1000.queries`, `search.10000.queries`, `vault.isolated_primary.scales`, `vault.stable_id_semantic`, `inbox_refreshAvailability_listItems.sizes`, `ui_nshosting_fixture.workflows`, `scan_cli.results`. Drivers: `benchmark_archive_search.sh`, `benchmark_vault_recovery.sh`, `benchmark_output_inbox.sh`, `benchmark_archive_ui.sh`, and the one-off `NikoMusicHubCLI export-index` harness. `benchmark_archive_workflows.sh` supplies only the separate `workflows_context` measurements.
