# Niko Music Hub — Composer Execution Plan

Last verified: 2026-05-25 10:01 CEST

## The ask

Build one clean native Swift music hub that combines:

1. **Cubase file organization / archive recall** — browse songs, hear best preview, open latest `.cpr`.
2. **Outside-Cubase tools** — BPM tapper, WAV converter, system-audio recorder, downloader, output inbox.

Requirements from Niko:

- New GitHub repo for the combined tool.
- No Hermes worker fan-out because billing is annoying.
- Cleanest architecture, well planned.
- Full Swift / native SwiftUI, using Automation Health style as reference.
- End-to-end tested like a user.
- Product code written by Composer 2.5 via Pi Agent SDK: planner → critic → executor → critic/reviewer.
- Do not mix with or disturb Locus/nightshift processes.

## New facts from MacBook discovery

### MacBook access

Verified from always-on `INTERNET`:

```bash
ssh macbook
```

Target:

- Hostname: `MBP-von-Niko`
- ComputerName: `MacBook Pro von Niko`
- Home: `/Users/niko`
- macOS: `26.5`

This is now saved in:

- Hermes memory
- Honcho conclusion
- `oldmac-file-retrieval` skill
- `/Users/nikolaymohr/.hermes/notes/niko-macbook-access.md`

### Outside-Cubase tool found

Canonical MacBook path:

```text
/Users/niko/Documents/OutSideCubaseHub
```

It is already a native SwiftPM / SwiftUI app. This is not a stub. It has real feature modules:

- `AppCore`
- `FeatureBPMTapper`
- `FeatureAudioConverter`
- `FeatureAudioRecorder`
- `FeatureDownloader`
- `OutsideCubaseHub`

Current state:

```text
154 tests passed
6 tests skipped because system-audio recording permission is not granted
0 failures
```

Git state:

```text
branch: main
modified: .DS_Store files only
```

Important: MacBook does **not** currently have `pi` or `gh`; `INTERNET` does. So Composer/GitHub orchestration should run from `INTERNET`, while MacBook is treated as a read-only source/reference unless explicitly copying source into the new repo.

### Cubase archive browser found on MacBook too

Canonical MacBook/iCloud path:

```text
/Users/niko/Library/Mobile Documents/com~apple~CloudDocs/Documents/02_PROJECTS/01_ACTIVE_PROJECTS/CUBASE FILE ORGA
```

It is the Electron/React app that shipped v1.0 on 2026-05-23.

Current state:

- v1.0 shipped per `.planning/PROJECT.md` and `docs/SPEC.md`.
- Strong product spec exists.
- Dirty files exist in scanner/selection code plus planning artifacts.
- No GitHub remote configured.

This is reference material, not the implementation base.

### New GitHub repo status

`Niko96-dotcom/niko-music-hub` does **not** exist yet.

## Strong architecture decision

Use **OutsideCubaseHub as the Swift seed**, not a blank rewrite.

The earlier blank-app plan was sane before discovery. Now that we found a tested Swift app with the exact outside-Cubase modules, starting from scratch would be stupid. Not noble. Just wasteful.

The clean path:

```text
NikoMusicHub
├── Existing outside-Cubase tools, renamed and kept modular
│   ├── BPM Tapper
│   ├── Audio Converter
│   ├── System Audio Recorder
│   ├── Downloader
│   └── Output Inbox
└── New Cubase Archive feature, ported from Electron spec into Swift
    ├── Song folder scanner
    ├── CPR version detection
    ├── Preview candidate ranking
    ├── Search / browse / detail
    └── Open latest .cpr
```

Translation: **keep the good Swift spine; port only the Cubase domain logic and UX contract.** Do not drag Electron, React, SQLite assumptions, or TypeScript build mess into the new app.

## Repo strategy

Create a new private repo:

```text
Niko96-dotcom/niko-music-hub
/Users/niko/Documents/Niko-Music-Hub
```

Why private first:

- early commits will contain personal archive assumptions
- local paths may leak
- music-production workflow details should be sanitized before public release

No GitHub Actions for now. Local truth gate only:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

## Machine/process isolation

### Locus boundary

Current `INTERNET` process table shows active Locus/nightshift processes. Therefore:

- Do not touch `/Users/nikolaymohr/locus`.
- Do not touch `/Users/nikolaymohr/.hermes/workers/locus-nightshift`.
- Do not set or depend on `LOCUS_*` env vars.
- Do not reuse Locus worktrees, caches, or scripts.
- No background Composer daemons.
- One Composer session at a time.
- Use lock file:

```bash
/tmp/niko-music-hub-composer.lock
```

Run Composer from `INTERNET` with lower priority while Locus is alive:

```bash
nice -n 10 env PATH=/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  pi --provider cursor --model composer-2.5 \
  --tools read,bash,edit,write,grep,find,ls \
  -p @.ai/prompts/01-planner.md
```

### MacBook boundary

MacBook is a source/reference machine unless a step explicitly says copy.

Allowed without extra approval:

- read docs/code
- run tests/builds in the existing MacBook project when relevant
- copy source/reference files into the new repo

Not allowed without explicit user approval:

- modifying MacBook source projects in place
- deleting/renaming music files
- installing new tools on MacBook
- changing system audio permissions

## Source import model

### Seed from OutsideCubaseHub

Copy the Swift app into the new repo as the starting point, then Composer renames/refactors it:

```bash
rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude 'dist' \
  --exclude '.DS_Store' \
  macbook:'/Users/niko/Documents/OutSideCubaseHub/' \
  '/Users/niko/Documents/Niko-Music-Hub/'
```

Then Composer owns:

- package rename: `OutsideCubaseHub` → `NikoMusicHub`
- bundle rename
- app shell rename
- module cleanup
- docs rewrite
- preserving all green tests

### Port from Cubase File Orga

Do not copy Electron source wholesale.

Allowed import:

- product spec: `docs/SPEC.md`
- design system intent: `docs/DESIGN_SYSTEM.md`
- scanner behavior requirements
- preview ranking policy ideas
- behavioral harness semantics

Composer should reimplement Cubase archive behavior in Swift modules.

## Proposed final package structure

```text
niko-music-hub/
  Package.swift
  README.md
  AGENTS.md
  docs/
    architecture.md
    product-scope.md
    source-inventory.md
    user-e2e.md
  Fixtures/
    CubaseArchive/
      Neon Hook/
        Neon Hook.cpr
        Mixdown/Neon Hook v3.wav
        Ideas/Neon Hook topline.mid
      Broken Folder Example/
        notes.txt
    OutsideTools/
      audio-inputs/
      downloader/
  Sources/
    NikoMusicCore/
      Domain/
        Song.swift
        ProjectVersion.swift
        PreviewCandidate.swift
        ExternalIdea.swift
        MusicRoot.swift
      Scanning/
        CubaseArchiveScanner.swift
        CPRVersionDetector.swift
        PreviewCandidateDetector.swift
        SongTitleResolver.swift
      Search/
        MusicSearchIndex.swift
      Opening/
        MusicItemOpener.swift
      Safety/
        PathSafety.swift
        ReadOnlyArchivePolicy.swift
    AppCore/
      existing outside-hub shared services
    FeatureArchiveBrowser/
      ArchiveBrowserFeature.swift
      ArchiveBrowserView.swift
      ArchiveBrowserViewModel.swift
      SongDetailView.swift
      PreviewPlayerView.swift
    FeatureBPMTapper/
    FeatureAudioConverter/
    FeatureAudioRecorder/
    FeatureDownloader/
    NikoMusicHub/
      NikoMusicHubApp.swift
      AppComposition.swift
      AppShell/
    NikoMusicCoreSelfTest/
      main.swift
  Tests/
    NikoMusicCoreTests/
    FeatureArchiveBrowserTests/
    existing outside-tool tests
  script/
    ci.sh
    e2e_user_smoke.sh
    build_and_run.sh
    sync_sources_from_macbook.sh
  .ai/
    prompts/
    runs/
    tasks/
```

## Architecture rules

### `NikoMusicCore`

Pure Swift. No SwiftUI. No AppKit UI. Owns the archive domain and safety.

Must include:

- one-folder-one-song scanner
- `.cpr` detection
- preview candidate detection
- preview confidence ranking
- latest `.cpr` selection by modification date
- app-owned metadata model
- search index
- fixture builders

### Existing `AppCore`

Keep the tested outside-tool infrastructure:

- `ToolFeature`
- `ToolRegistry`
- `ToolContext`
- `JobRunner`
- `OutputInbox`
- `SettingsStore`
- shared errors/components

Do not collapse this into the archive browser. That would be architecture vandalism.

### `FeatureArchiveBrowser`

SwiftUI feature module registered through the same `ToolFeature` boundary as BPM/converter/recorder/downloader.

It must feel like the “home” feature of the hub, but technically it stays a feature.

### Existing outside features

Keep as modules:

- `FeatureBPMTapper`
- `FeatureAudioConverter`
- `FeatureAudioRecorder`
- `FeatureDownloader`

Rename copy where needed, but preserve tests.

## Product scope v0.1

### Must ship

1. Native `.app` named **Niko Music Hub**.
2. Existing outside-Cubase tools still work:
   - BPM tapper
   - WAV converter
   - system audio recorder shell/permission handling
   - downloader
   - output inbox
3. New archive browser feature:
   - opt-in root selection
   - scan fixture Cubase archive
   - one folder = one song
   - detect `.cpr` versions
   - detect preview audio
   - rank main preview
   - search by title/folder/preview/CPR
   - detail page with previews and CPR versions
   - open/reveal latest `.cpr` in dry-run fixture mode
4. All current OutsideCubaseHub tests still pass after rename/import.
5. New archive core tests pass.
6. E2E smoke launches the app and performs the real user path.
7. Real archive smoke is read-only only.

### Not v0.1

- Deep `.cpr` parsing.
- Cubase plugin/VST integration.
- Moving/renaming/deleting real files.
- Cloud sync.
- Public release signing/notarization.
- AI generation embedded in app.
- Migrating old Electron database.

## Composer role sequence

No Hermes workers. No parallel subagents.

### Step 1 — Hermes bootstrap only

Hermes creates repo, copies source, writes prompts. Product code untouched except mechanical seed copy.

### Step 2 — Composer Planner

Composer reads:

- this plan
- copied OutsideCubaseHub source/tests
- Automation Health package structure
- Cubase `docs/SPEC.md`
- Cubase `.planning/PROJECT.md`

Composer writes only docs/tasks:

- `docs/source-inventory.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `.ai/tasks/v0.1-task-queue.json`

No product code.

### Step 3 — Composer Critic

Composer attacks the plan:

- scope creep
- unsafe file operations
- Electron leakage
- broken test strategy
- missing E2E
- Locus contamination
- MacBook/INTERNET split problems

Outputs:

- `docs/critic-review-01.md`
- patches to docs/tasks only

### Step 4 — Composer Executor

Composer implements in small commits:

1. Rename/package cleanup while preserving tests.
2. Add `NikoMusicCore` and fixture scanner tests.
3. Add archive search/detail model tests.
4. Add `FeatureArchiveBrowser` UI skeleton.
5. Wire archive browser into app shell.
6. Add E2E fixture smoke.
7. Add real read-only scanner smoke.
8. Polish naming/docs.

After each slice:

```bash
./script/ci.sh
```

Commit only green states.

### Step 5 — Composer Critic/Reviewer

Composer reviews final diff against plan and writes:

- `docs/final-review.md`
- defects list or approval

### Step 6 — Hermes verification

Hermes independently runs:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
git status --short
git log --oneline -5
```

Then launches/checks app like a user if safe.

## Local test gates

### CI gate

`./script/ci.sh` should run:

```bash
swift build
swift test
swift run NikoMusicCoreSelfTest
```

### E2E gate

`./script/e2e_user_smoke.sh` should:

1. Build `.app`.
2. Reset test Application Support.
3. Launch app with fixture root and dry-run open mode.
4. Assert app process started.
5. Run scripted debug route if available, or use Accessibility automation.
6. Search fixture song `Neon Hook`.
7. Select it.
8. Verify preview and `.cpr` are visible.
9. Trigger Open Latest.
10. Assert dry-run log captured expected `.cpr` path.

### Real archive smoke

Read-only scanner CLI/self-test mode:

```bash
swift run NikoMusicCoreSelfTest --real-root "/path/to/cubase/root" --read-only
```

Acceptance:

- reports counts for songs, CPRs, previews
- writes only app-owned metadata under test Application Support/tmp
- zero writes under scanned music roots

## First Composer planner prompt

Save as `.ai/prompts/01-planner.md` after bootstrap:

```markdown
You are Composer 2.5 running via Pi Agent SDK. You are the planner for Niko Music Hub.

Repo: /Users/niko/Documents/Niko-Music-Hub
Mission: turn the existing Swift OutsideCubaseHub seed plus Cubase archive browser spec into one clean native SwiftUI app called Niko Music Hub.

Hard rules:
- Full Swift/SwiftUI. No Electron runtime, no React, no TypeScript in product code.
- Use OutsideCubaseHub as the Swift seed; preserve its outside-Cubase feature modules and tests.
- Reimplement Cubase archive browsing in Swift from spec/behavior, not by embedding Electron code.
- No Hermes workers, no parallel agents, no GitHub Actions requirement.
- No Locus interaction: do not touch /Users/nikolaymohr/locus or ~/.hermes/workers/locus-nightshift.
- Never rename, move, delete, or rewrite real music/archive files.
- Fixture-first tests and user-style E2E are mandatory.

Inspect first:
- /Users/nikolaymohr/.hermes/plans/2026-05-25_1001-niko-music-hub-composer-execution-plan.md
- /Users/niko/Documents/Niko-Music-Hub/Package.swift
- /Users/niko/Documents/Niko-Music-Hub/Sources/AppCore/Features/ToolRegistry.swift
- /Users/niko/Documents/Niko-Music-Hub/Sources/OutsideCubaseHub/AppComposition.swift
- /Users/nikolaymohr/src/automation-health/Package.swift
- /Users/nikolaymohr/src/automation-health/Sources/AutomationHealth/App/AutomationHealthApp.swift
- copied reference docs under docs/reference/cubase-file-orga/

Output only docs and task queue:
- docs/source-inventory.md
- docs/product-scope.md
- docs/architecture.md
- .ai/tasks/v0.1-task-queue.json

Do not write product code yet.
```

## Bootstrap commands when Niko says go

```bash
set -euo pipefail

REPO=/Users/niko/Documents/Niko-Music-Hub
SRC_MACBOOK=/Users/niko/Documents/OutSideCubaseHub
CUBASE_REF="/Users/niko/Library/Mobile Documents/com~apple~CloudDocs/Documents/02_PROJECTS/01_ACTIVE_PROJECTS/CUBASE FILE ORGA"

# Create private GitHub repo + local working dir
gh repo create Niko96-dotcom/niko-music-hub \
  --private \
  --description "Native local-first SwiftUI hub for Cubase archives and outside-Cubase music tools" \
  --clone "$REPO"

# Seed from tested Swift OutsideCubaseHub
rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude 'dist' \
  --exclude '.DS_Store' \
  macbook:"$SRC_MACBOOK/" \
  "$REPO/"

mkdir -p "$REPO/docs/reference/cubase-file-orga"
rsync -a \
  macbook:"$CUBASE_REF/docs/SPEC.md" \
  "$REPO/docs/reference/cubase-file-orga/SPEC.md"
rsync -a \
  macbook:"$CUBASE_REF/docs/DESIGN_SYSTEM.md" \
  "$REPO/docs/reference/cubase-file-orga/DESIGN_SYSTEM.md"
rsync -a \
  macbook:"$CUBASE_REF/.planning/PROJECT.md" \
  "$REPO/docs/reference/cubase-file-orga/PROJECT.md"

cd "$REPO"
mkdir -p .ai/prompts .ai/tasks script docs
swift test
```

## Definition of done

This is done when:

- `Niko96-dotcom/niko-music-hub` exists.
- App is native SwiftUI and named **Niko Music Hub**.
- Existing outside-Cubase modules still pass their tests.
- Archive browser is implemented in Swift with fixture tests.
- App launches from a `.app` bundle.
- Fixture E2E passes like a user.
- Real archive scan smoke passes read-only.
- No Locus files/processes touched.
- No real music files renamed/moved/deleted.
- Composer wrote the product code through sequential Pi runs.
- Hermes independently verified the result.

## My take

The right move changed after discovery: **do not start blank.** We already have a tested Swift outside-Cubase hub on the MacBook. Use it as the spine, port Cubase archive behavior into it, rename the product, and put the combined thing in a clean new repo.

A blank rewrite now would be purity cosplay. A direct Electron/Python merge would be cursed. This adapter-style Swift consolidation is the boring correct answer.
