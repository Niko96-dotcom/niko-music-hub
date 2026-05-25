# Critic Review 01 — Niko Music Hub v0.1

Last verified: 2026-05-25  
Role: Composer 2.5 critic (docs/tasks only)

## Verdict

The planner produced a **sound domain-first slice order** and correctly centers the OutsideCubaseHub seed, pure `NikoMusicCore`, and read-only archive safety. The plan is executable.

It is **not yet safe to call v0.1 done** without tightening: fixture generation, E2E proof (not process-alive theater), rename blast radius, preview-ranker scope, and explicit bans on string-inspection tests for new archive code.

The execution plan’s executor order (rename first) **diverges** from the task queue (rename at slice 06). **Follow the task queue**; the critic moved rename guardrails into slice 06 rather than reordering.

---

## Attack summary

### Scope creep (moderate)

| Area | Finding |
|------|---------|
| Preview ranker | Slice 03 + architecture ask for full SPEC §8 six-step ranking, duration plausibility, and `confidenceReasons[]`. That is Milestone 1++ / Electron parity, not a minimal v0.1 slice. |
| Metadata | Optional `archive-cache.json` in architecture invites persistence work before browse UI ships. Defer to post-v0.1. |
| UX | `DESIGN_SYSTEM.md` editorial home + waveform hero + smart shelves language leaks into slices 08–09. v0.1 should be **dark tokens + list/detail + simple bar**, not shelf system or chorus-biased preview start. |
| Dev tool | Slice 13 bundles doc polish with dev-tool policy — fine, but do not expand DevTool for archive debugging; use a dedicated smoke CLI. |

### Unsafe real-file operations (controlled if gates hold)

- Product-scope and safety boundaries are correct: read-only archive roots, dry-run open for fixtures/E2E.
- **Gap:** slice 12 “zero writes under scanned root” is manual-only unless `ReadOnlyArchivePolicyTests` includes a **write-probe** (create temp file under fixture root, expect denial).
- **Gap:** `MusicItemOpener` non-dry-run must never run in CI; tests must inject a fake workspace port (task queue mentions this — keep it mandatory).
- Outside tools (converter, downloader, recorder) **write output files** by design; that is not archive scope. Do not conflate “read-only hub” with “no writes anywhere.”

### Electron / React / TypeScript leakage (low risk if executor obeys)

- Reference docs correctly quarantined under `docs/reference/cubase-file-orga/`.
- No product leakage today. Risk is **porting SQLite/chokidar/FlexSearch mental model** into Swift (JSON cache + watcher tasks). Non-goals already list these; critic reinforced in task queue.

### Module boundaries (good with one UI tension)

- `NikoMusicCore` pure / `FeatureArchiveBrowser` / `AppCore` split matches AGENTS.md and automation-health’s core-vs-app pattern.
- **Tension:** product-scope wants archive as “home” with editorial layout, but seed `AppShellView` is a fixed **3-column tool shell** (sidebar | tool | inbox) defaulting to `wav-converter`. v0.1 should register `archive-browser` first and default-select it, but **must not** rewrite the whole shell to Automation Health’s single-window layout in one slice. Archive gets a nested browse/detail layout inside the center column only.

### E2E (high risk — currently fake)

- `script/e2e_user_smoke.sh` exits **2** (stub). v0.1 DoD requires green E2E.
- Slice 11 is late; slices 08–10 mark `fixture_e2e: planned` without enforcement — acceptable only if executor does not claim browse UI “done” without a runnable gate.
- **Critical:** acceptance must not reduce to `pgrep NikoMusicHub`. Must assert: fixture root loaded, search returns Neon Hook, dry-run log contains fixture CPR path. Prefer **`NikoMusicHub` debug/CLI hook** (env-driven) over flaky Accessibility-only osascript.

### Fixtures (missing — blocking)

- **Zero** files under `Fixtures/` today.
- Slice 01 lists binary `.cpr` / `.wav` paths but not **how** to create them. Copying real Cubase projects risks personal data and huge binaries.
- Architecture mentions `Second Song/`; task queue slice 01 did not — ranker tie-break tests need a second song with competing previews.
- Execution plan `Fixtures/OutsideTools/` is absent from task queue (OK for v0.1 if outside tests keep building their own temp dirs).

### String-inspection tests (seed antipattern — do not spread)

Existing seed tests read Swift source as strings (`source.contains`) in converter, inbox, downloader, FFmpeg tests. That is **brittle** and not behavior verification.

**New archive tests must not copy this pattern.** Use fixture filesystem walks, ranker outputs, and injected opener fakes only.

### Locus contamination (low in product; note orchestration)

- Task queue `no_locus_paths` matches AGENTS.md.
- `script/run_composer_sequence.sh` uses `~/.hermes/workers/niko-music-hub-composer` — **not** an AGENTS-forbidden locus path, but executor must not import `LOCUS_*`, touch `locus`, or run parallel Hermes coding workers.
- Lock file `/tmp/niko-music-hub-composer.lock` is fine.

### MacBook / INTERNET split (planner doc drift)

- `docs/niko-music-hub-composer-execution-plan.md` still says MacBook may “run tests/builds in the existing MacBook project when relevant.” That contradicts AGENTS.md (**read-only / rsync only**). Planner docs tightened in `docs/source-inventory.md`.

### Over-broad commits (slice 06)

- Slice 06 combines Package rename, directory moves, bundle id, Application Support path, `build_and_run.sh`, and full CI — one commit will be painful to bisect. Task queue now requires **two green commits** inside the slice.

### Automation Health / SwiftUI style

- Package pattern (`*Core` + `*SelfTest` + `App` activation delegate) aligns with automation-health.
- **Do not** mirror Automation Health’s single `ContentView` shell; keep tool registry spine.
- Do mirror: `AppDelegate` activation, self-test executable in CI, restrained typography/spacing from DESIGN_SYSTEM tokens — not a pixel-perfect Electron clone.

---

## Top 10 risks (likelihood × damage)

Sorted by approximate risk score (likelihood × damage, highest first).

| # | Risk | L | D | Mitigation |
|---|------|---|---|------------|
| 1 | **E2E passes on process-alive only** | High | High | Mandatory CLI/debug smoke + dry-run log assertion in slice 11; forbid pgrep-only success |
| 2 | **No real fixtures → scanner/ranker tests lie** | High | High | `script/fixtures/generate_cubase_archive_fixtures.sh` + Second Song; minimal valid WAV; zero-byte CPR placeholder documented |
| 3 | **Slice 06 rename breaks 154-test baseline** | Med-High | High | Two-commit split; run `./script/ci.sh` between; no drive-by refactors |
| 4 | **Preview ranker scope absorbs v0.1** | High | Med | v0.1 ranker = role + folder + filename tokens + recency only; defer duration/chorus/version tiebreaks |
| 5 | **Real-root scan writes into archive** | Med | Catastrophic | Write-probe unit test + self-test `--read-only` verification in slice 12 |
| 6 | **Archive UI crushed in 3-column shell** | Med | Med | Nested NavigationSplit inside archive feature; default tool = archive-browser |
| 7 | **New tests use `source.contains` inspection** | Med | Med | Explicit ban in critic_checklist; code review in slice 07+ |
| 8 | **Dry-run open leaks to real Cubase launch** | Low-Med | High | Env `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` default in E2E; unit tests never call real NSWorkspace |
| 9 | **JSON cache written under music root** | Low-Med | High | v0.1 in-memory only; cache path only under Application Support |
| 10 | **Executor follows execution-plan rename-first** | Med | Med | `executor_order` in task queue is authoritative; critic review overrides plan §Step 4 ordering |

---

## Task queue patches applied

See `.ai/tasks/v0.1-task-queue.json` changelog in `critic_patches` array. Summary:

1. **Slice 01** — fixture generator script, `Second Song` competitor tree, ban string-inspection tests in new targets.
2. **Slice 03** — narrowed ranker acceptance (v0.1 subset of SPEC §8).
3. **Slice 06** — `commit_policy: split-two-commits` with explicit sub-acceptance.
4. **Slice 07** — add `ArchiveSmokeCommands` / env-driven debug entry for automation.
5. **Slice 11** — E2E must assert dry-run log + CLI hook; osascript optional only.
6. **Slice 12** — automated write-probe required, not manual-only.
7. **critic_checklist** — expanded with E2E, fixture, and test-quality gates.
8. **non_goals** — JSON archive cache, smart shelves, chorus preview start.
9. **executor_first_slice** — explicit pointer for executor prompt.

## Planner doc patches applied

- `docs/source-inventory.md` — MacBook read-only rule, seed string-test warning, E2E stub callout.
- `docs/product-scope.md` — v0.1 ranker subset, shell strategy clarified, cache deferred.
- `docs/architecture.md` — nested archive UI note, v0.1 ranker scope, cache deferred.

---

## Executor’s first safe slice

**Slice `01-fixtures-and-core-skeleton`**

Deliver in order:

1. `script/fixtures/generate_cubase_archive_fixtures.sh` — creates `Fixtures/CubaseArchive/Neon Hook/`, `Second Song/`, `Broken Folder Example/` with minimal valid `.wav`, placeholder `.cpr`, and `notes.txt`.
2. `Package.swift` — add `NikoMusicCore` library target + `NikoMusicCoreTests` (no app rename yet).
3. Domain + `PathSafety` + `ReadOnlyArchivePolicy` with **behavior tests** (path outside roots rejected; write-probe denied under fixture root).
4. `./script/ci.sh` green before commit.

Do **not** start package rename, `FeatureArchiveBrowser`, or E2E script in slice 01.
