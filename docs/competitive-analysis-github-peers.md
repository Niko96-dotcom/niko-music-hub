# Competitive analysis: GitHub peers vs Niko Music Hub

**Last updated:** 2026-05-30  
**Purpose:** Map similar open-source (and one commercial reference) products to Niko Music Hub capabilities, identify gaps and strengths, and produce a **prioritized backlog** aligned with `docs/reference/cubase-file-orga/SPEC.md` milestones plus **net-new** ideas from the field.

**Sources:** GitHub READMEs and public docs (May 2026), this repo’s `README.md`, `Sources/`, hub-polish waves A–G (done), and `docs/reference/cubase-file-orga/SPEC.md`.

---

## Executive summary

| Dimension | Finding |
|-----------|---------|
| **Closest overall peer** | [bandpassrecords/daw-project-manager](https://github.com/bandpassrecords/daw-project-manager) — multi-DAW project library with metadata, todos, releases, sync |
| **Closest Cubase-specific peer** | [schwifty00/CubaseTools](https://github.com/schwifty00/CubaseTools) — `.cpr` reverse engineering, cross-project analytics, **destructive** cleanup |
| **Same job-to-be-done (recall)** | Fruity Server (FL), dBdone (commercial, Ableton) — preview renders without opening the DAW |
| **Niko’s unique wedge** | Native Swift **hub**: Cubase **song-folder** recall (read-only) + outside-Cubase tools + shared **output inbox** |
| **Biggest gaps vs field** | Persistent scan DB + file watching, editable metadata layer, smart shelves, waveform preview UX, file/BPM from mixdowns, optional read-only `.cpr` intelligence |
| **Biggest advantage vs field** | Preview maturity ranking, non-destructive archive policy, integrated converter/recorder/downloader, Cubase-tuned folder semantics |

---

## Methodology

1. **Baseline** — What Niko Music Hub ships in Swift today (not the Electron reference app on MacBook).
2. **Peers** — GitHub repos in four buckets: project libraries, Cubase/DAW parsers, preview/recall UIs, tool modules (BPM, samples, recorders).
3. **Mapping** — Each backlog item tagged:
   - **SPEC-M*n*** — Already in Cubase File Orga `SPEC.md` milestone *n*
   - **NET-NEW** — Valuable from peers, not explicit in SPEC (or explicitly a non-goal in SPEC v1)
   - **HUB** — Outside-Cubase tool / inbox improvements
4. **Priority** — P0 (high recall impact), P1 (strong polish), P2 (strategic / optional), P3 (defer or conflict)

Non-goals from SPEC §12 are respected unless marked **P3 / reconsider**.

---

## Niko Music Hub baseline

### Shipped today (Swift)

| Area | Status | Notes |
|------|--------|-------|
| Archive roots | ✅ | Persist via `SettingsStore`; dev default root; fixture env override |
| Scan → songs | ✅ | One child folder = one song; `.cpr` + preview detection |
| Preview ranking | ✅ | Confidence ranker + maturity ladder (hub-polish A); stems demotion |
| Display title | ✅ | From folder + winning preview (`SongTitleResolver`) |
| Play preview | ✅ | `ArchiveMiniPlayerView` (compact + detail) |
| Open latest `.cpr` | ✅ | Read-only; dry-run env for automation |
| Search | ✅ Partial | Title, folder, CPR/preview filenames, `notes.txt`, scan warnings; token + subsequence |
| Sidecar notes | ✅ | Read `notes.txt` at song root |
| Sidebars / inbox chrome | ✅ | Hub-polish F |
| BPM tapper | ✅ | Manual tap; algorithm polish (wave D) |
| WAV converter | ✅ | Native + FFmpeg; inbox handoff |
| Recorder | ✅ | System audio (Core Audio / SCK path per phase 8) |
| Downloader | ✅ | yt-dlp; format pickers (wave C) |
| Output inbox | ✅ | Cross-tool files, drag-out |
| Settings | 🚧 | Launch at login, privacy deep-links (in progress on branch) |

### In Electron SPEC / design, not in Swift yet

| SPEC area | Milestone |
|-----------|-----------|
| Virtual rename, aliases, editable song/version notes | M2 |
| Manual choose main preview / main `.cpr` | M2 |
| Collaborators + address book | M2 |
| Smart shelves (Recently Bounced, Recent CPR, Has Stems, By Collaborator) | M3 |
| Search: aliases, collaborator names, virtual title | M3 |
| New song wizard (folder + template + open Cubase) | M4 |
| Collaborator suggestions UI | M5 |
| Waveform hero, loudness-based preview start | M5 |
| SQLite persistence, incremental scan, file watching | Scanner §7 (cross-cutting) |
| First-run root selection flow | Screen inventory |

### Explicit SPEC non-goals (v1)

Do **not** plan as P0 without product decision: cloud sync, multi-user collab, public sharing, full DAW-agnostic support, heavy manual tagging, **deep `.cpr` parsing as core dependency**, becoming a generic sample manager.

---

## Peer catalog

### Tier A — Direct competitors (project / archive recall)

#### [bandpassrecords/daw-project-manager](https://github.com/bandpassrecords/daw-project-manager)

| | |
|---|---|
| **Stack** | Flutter, Hive, macOS primary |
| **Model** | One **project file** per row (`.cpr`, `.als`, `.logicx`, …) |
| **Strengths** | 10+ DAWs; two-phase scan; BPM/key/version metadata extraction; todos & phases; releases; cross-project task queue; statistics; profiles; Google Drive sync; fuzzy search; keyboard shortcuts (P/O/D/F); preview player with seek |
| **Weaknesses vs Niko** | Not song-folder-first; not read-only-by-default; no integrated converter/recorder/downloader/inbox |
| **Borrow risk** | Scope creep into generic DAW manager |

#### [schwifty00/CubaseTools](https://github.com/schwifty00/CubaseTools)

| | |
|---|---|
| **Stack** | Python 3.12+, tkinter GUI |
| **Model** | Per-`.cpr` **parse** + optional folder cleanup |
| **Strengths** | Plugin chains, EQ curves, compressor table, routing; cross-project plugin dashboard; JSON export; unused audio detection |
| **Weaknesses vs Niko** | No song-card preview UX; destructive cleanup; no “open latest CPR” recall flow |
| **Borrow risk** | Violates read-only archive policy if cleanup is copied |

#### Commercial: [dBdone](https://dbdone.com) (not OSS)

| | |
|---|---|
| **Model** | Disk scan → project list → **instant pre-listen** (Ableton-focused marketing) |
| **Strengths** | UX narrative around “preview without opening Live”; full-library discovery |
| **Relevance** | Same **recall** job as archive browser; validates mixdown-based preview strategy for Cubase |

#### [DreamerDeLy/fruity-server](https://github.com/DreamerDeLy/fruity-server)

| | |
|---|---|
| **Stack** | Nuxt web app |
| **Model** | FL Studio folders → play **renders**; optional `.flp` metadata |
| **Strengths** | Waveform scrubbing; multi-root config; streaming with range requests |
| **Relevance** | Parallel DAW; best reference for **preview player UX** |

---

### Tier B — DAW project intelligence (parse, batch, agents)

| Repo | Focus | Notable capabilities |
|------|--------|----------------------|
| [closestfriend/ableton-proj-mcp](https://github.com/closestfriend/ableton-proj-mcp) | `.als` MCP | Batch scan, plugin inventory, missing samples, duplicate hashing, JSON for agents |
| [glenandrewbrown/logicx-analyzer](https://github.com/glenandrewbrown/logicx-analyzer) | `.logicx` | MetaData.plist + binary plugin/preset extraction |
| [omeriko9/Cubase-Project-File-Reverse-Engineering](https://github.com/omeriko9/Cubase-Project-File-Reverse-Engineering) | Legacy `.cpr` | VST mixer view; ancient Cubase 2/3 only — research artifact |
| [orchetect/DAWFileKit](https://github.com/orchetect/DAWFileKit) | Swift library | Cubase Track Archive **XML** (markers); tempo ramp limitations |

---

### Tier C — Sample / media libraries (adjacent)

| Repo | Focus | Relevant ideas |
|------|--------|----------------|
| [lopadz/crate](https://github.com/lopadz/crate) | macOS sample browser | Instant playback, SQLite, BPM/key/LUFS, AI similarity search, cloud sync |
| [thetheosopher/SampleWrangler](https://github.com/thetheosopher/SampleWrangler) | Windows JUCE | Waveform cache, ASIO preview, catalog DB |
| [iversonianGremling/SampleSolution](https://github.com/iversonianGremling/SampleSolution) | Web + desktop | Tags, duplicates, bulk rename, slice view |
| [macvfx/p5ArchiveSearch](https://github.com/macvfx/p5ArchiveSearch) | P5 archive index | Tree browse, offline SQLite search, export CSV/JSON |
| [rebelonion/audio-share](https://github.com/rebelonion/audio-share) | Web library | Folder nav + global search index |

**SPEC non-goal:** “generic sample manager” — borrow **patterns** (waveform, DB), not product pivot.

---

### Tier D — Tool modules (overlap with Outside-Cubase features)

| Repo | Overlap with Niko tool | They do better |
|------|------------------------|----------------|
| [ryanfrancesconi/spfk-tempo](https://github.com/ryanfrancesconi/spfk-tempo) | BPM | **File** tempo: spectral flux + autocorrelation |
| [hPerezz/bpm-kit](https://github.com/hPerezz/bpm-kit) | BPM | Simple `estimateBPM(from: URL)` API |
| [Soham041201/Multi-music](https://github.com/Soham041201/Multi-music) | Preview/analysis | Waveform + beat grid on track load |
| [sachin6174/Guitar-Utility](https://github.com/sachin6174/Guitar-Utility) | BPM tapper | Tuner + metronome + subdivisions |
| [nonstrict-hq/ScreenCaptureKit-Recording-example](https://github.com/nonstrict-hq/ScreenCaptureKit-Recording-example) | Recorder | SCK reference implementation |
| [O4FDev/electron-system-audio-recorder](https://github.com/O4FDev/electron-system-audio-recorder) | Recorder | SCK audio-only stream patterns |

---

## Feature matrix (selected)

Legend: ✅ shipped · 🟡 partial · ⬜ missing · 🚫 SPEC non-goal v1 · ⚠️ conflicts with read-only policy

| Capability | Niko Hub | DAW PM | CubaseTools | Fruity Server | Crate | ableton-proj-mcp |
|------------|----------|--------|-------------|---------------|-------|------------------|
| Song-folder = one song | ✅ | ⬜ | ⬜ | ✅ (FL folder) | ⬜ | ⬜ |
| Mixdown preview without DAW | ✅ | 🟡 | ⬜ | ✅ | ✅ (samples) | ⬜ |
| Open latest project file | ✅ | ✅ | ⬜ | ⬜ | ⬜ | ⬜ |
| Read-only archive default | ✅ | ⬜ | ⚠️ cleanup | ✅ | ⬜ | ✅ |
| Multi-DAW | 🚫 | ✅ | Cubase only | FL | DAW-agnostic samples | Ableton |
| Parse `.cpr` internals | 🚫 core | 🟡 metadata | ✅ deep | 🟡 `.flp` | ⬜ | — |
| Plugin inventory across library | ⬜ | ⬜ | ✅ | ⬜ | ⬜ | ✅ |
| Unused audio cleanup | 🚫 | ⬜ | ⚠️ | ⬜ | ⬜ | ⬜ |
| Todos / phases / releases | ⬜ | ✅ | ⬜ | ⬜ | ⬜ | ⬜ |
| Cloud sync | 🚫 | ✅ | ⬜ | ⬜ | ✅ paid | ⬜ |
| Waveform scrub preview | ⬜ | 🟡 | ⬜ | ✅ | ✅ | ⬜ |
| Smart shelves / filters | ⬜ | 🟡 | ⬜ | ⬜ | ✅ collections | ⬜ |
| Persistent scan + watch | ⬜ | ✅ | ⬜ | ⬜ | ✅ | ⬜ |
| WAV converter + inbox | ✅ | ⬜ | ⬜ | ⬜ | 🟡 convert | ⬜ |
| System audio recorder | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| URL downloader | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| Tap tempo | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |
| File BPM detection | ⬜ | ✅ | ⬜ | 🟡 | ✅ | ⬜ |

---

## Backlog mapped to SPEC milestones

Priority key: **P0** = recall-critical · **P1** = high polish · **P2** = valuable later · **P3** = defer / needs product call

### Milestone 1 — Core archive browser (SPEC §6 M1)

| ID | Item | Swift status | Peer signal | Priority |
|----|------|--------------|-------------|----------|
| M1-01 | Choose archive root(s) | ✅ | DAW PM | — |
| M1-02 | Scan folders → songs | ✅ | DAW PM, Fruity | — |
| M1-03 | Detect `.cpr` versions | ✅ | CubaseTools | — |
| M1-04 | Detect preview candidates | ✅ | Fruity, dBdone | — |
| M1-05 | Play main preview | ✅ | Fruity, Crate | — |
| M1-06 | Open latest `.cpr` | ✅ | DAW PM | — |
| M1-07 | First-run root selection UX | ⬜ | DAW PM onboarding | **P1** |
| M1-08 | **Incremental scan + file watching** | ⬜ | SPEC §7; p5ArchiveSearch; DAW PM | **P0** |
| M1-09 | **Persist song index (SQLite)** — no full rescan every launch | ⬜ | SPEC §7; Crate; p5ArchiveSearch | **P0** |
| M1-10 | Keyboard shortcuts: preview / open / folder / detail | ⬜ | DAW PM (P/O/D/F) | **P1** |

**Net-new under M1 infrastructure:**

| ID | Item | Tag | Peer | Priority |
|----|------|-----|------|----------|
| M1-N1 | Export scan diagnostics / song list JSON (CLI or menu) | NET-NEW | CubaseTools JSON; p5ArchiveSearch CSV | **P2** |
| M1-N2 | Archive health report: songs with no preview, no CPR, warnings count | NET-NEW | ableton-proj-mcp “missing samples” pattern | **P1** |

---

### Milestone 2 — App metadata layer (SPEC §6 M2)

| ID | Item | Swift status | Peer signal | Priority |
|----|------|--------------|-------------|----------|
| M2-01 | Virtual rename (`display_title` override, disk unchanged) | ⬜ | DAW PM display name | **P0** |
| M2-02 | Aliases (searchable JSON list) | ⬜ | — | **P1** |
| M2-03 | Editable song notes (app DB, not only `notes.txt`) | ⬜ | DAW PM notes | **P0** |
| M2-04 | Version notes per `.cpr` | ⬜ | — | **P2** |
| M2-05 | Collaborators + address book | ⬜ | SPEC §9 | **P1** |
| M2-06 | Manual choose main preview (auto/manual mode) | ⬜ | SPEC §8 overrides | **P0** |
| M2-07 | Manual choose main `.cpr` | ⬜ | SPEC §8 | **P1** |
| M2-08 | Ignore song / ignore candidate flags | ⬜ | DAW PM hide/unhide | **P1** |

**Net-new under M2:**

| ID | Item | Tag | Peer | Priority |
|----|------|-----|------|----------|
| M2-N1 | **BPM from main mixdown** (display only, no manual entry) | NET-NEW | bpm-kit, spfk-tempo, DAW PM deep scan | **P1** |
| M2-N2 | **Musical key from mixdown** (optional, display only) | NET-NEW | DAW PM, Crate | **P2** |
| M2-N3 | Show DAW version / project file size on detail | NET-NEW | DAW PM metadata extractor | **P2** |

---

### Milestone 3 — Stronger browse / search (SPEC §6 M3)

| ID | Item | Swift status | Peer signal | Priority |
|----|------|--------------|-------------|----------|
| M3-01 | Smart shelf: Recently Bounced | ⬜ | SPEC §10 | **P0** |
| M3-02 | Smart shelf: Recent CPR Activity | ⬜ | SPEC §10 | **P0** |
| M3-03 | Smart shelf: Has Stems | ⬜ | SPEC §10 | **P1** |
| M3-04 | Smart shelf: By Collaborator | ⬜ | SPEC §10 | **P1** (blocked on M2-05) |
| M3-05 | Search virtual title + aliases | ⬜ | DAW PM fuzzy | **P1** (blocked on M2) |
| M3-06 | Search collaborator names | ⬜ | — | **P1** (blocked on M2-05) |
| M3-07 | Query: recent CPR changed | ⬜ | SPEC §10 | **P0** (shelf + search) |
| M3-08 | Home browse with curated shelves (not flat list only) | ⬜ | SPEC screens | **P1** |
| M3-09 | Fuzzy search upgrade (ranking, typos) | 🟡 subsequence only | DAW PM `fuzzyMatchAll` | **P2** |

**Net-new under M3:**

| ID | Item | Tag | Peer | Priority |
|----|------|-----|------|----------|
| M3-N1 | Sort modes: recent bounce, recent CPR, title A–Z | NET-NEW | DAW PM table sort | **P1** |
| M3-N2 | Filter chips in archive sidebar (stems / no preview / warnings) | NET-NEW | SampleSolution filters | **P1** |

---

### Milestone 4 — New song flow (SPEC §6 M4)

| ID | Item | Swift status | Peer signal | Priority |
|----|------|--------------|-------------|----------|
| M4-01 | New Song modal (name, collaborators, template, note) | ⬜ | — | **P2** |
| M4-02 | Create folder + standard subfolders (`Mixdown`, `Stems`) | ⬜ | SPEC §11 | **P2** |
| M4-03 | Instantiate Cubase project from template | ⬜ | SPEC §11 (orchestration) | **P2** |
| M4-04 | Register song in index + open Cubase | ⬜ | — | **P2** |

**Note:** M4 is **creation** workflow; peers rarely implement this well. Lower priority than recall (M1–M3) unless active-project workflow is urgent.

---

### Milestone 5 — Polish (SPEC §6 M5)

| ID | Item | Swift status | Peer signal | Priority |
|----|------|--------------|-------------|----------|
| M5-01 | Collaborator suggestions (review yes/no) | ⬜ | SPEC §9 | **P2** |
| M5-02 | Improved preview confidence (ongoing) | 🟡 | — | **P1** |
| M5-03 | **Waveform hero** on song detail | ⬜ | Fruity Server; DESIGN_SYSTEM | **P0** |
| M5-04 | Seek controls (±5s, ±30s) | ⬜ | DAW PM player | **P1** |
| M5-05 | Preview start at loud section (heuristic) | ⬜ | SPEC §8 | **P2** |
| M5-06 | Full `.cpr` version list UI on detail | 🟡 partial | — | **P1** |
| M5-07 | Preview candidates list + override UI | 🟡 alternates only | — | **P1** (ties M2-06) |

**Net-new under M5:**

| ID | Item | Tag | Peer | Priority |
|----|------|-----|------|----------|
| M5-N1 | Scrubbable playhead on cards (compact waveform) | NET-NEW | Fruity Server | **P1** |
| M5-N2 | “Open in Cubase” vs “Reveal CPR” vs “Reveal folder” clarity | NET-NEW | DAW PM quick actions | **P1** |

---

## Net-new backlog (not in SPEC milestones)

Items worth tracking that came from GitHub/commercial peers but are **outside** SPEC §6 numbering or **explicit non-goals**.

| ID | Item | Rationale | Peer | Priority | SPEC alignment |
|----|------|-----------|------|----------|----------------|
| NN-01 | **Read-only CPR plugin summary** on song detail | “What plugins did I use on this track?” without opening Cubase | CubaseTools | **P2** | §12 says no *core* deep parse; optional read-only sidebar OK |
| NN-02 | **Cross-library plugin stats** screen | See VST usage across all songs | CubaseTools dashboard | **P3** | Scope expansion |
| NN-03 | **Duplicate song folder detection** (similar CPR hashes or folder names) | Find redundant projects | ableton-proj-mcp | **P2** | Not in SPEC |
| NN-04 | **Missing / unreferenced audio report** (read-only) | Archive hygiene without delete | CubaseTools analyze-only mode | **P2** | Conflicts if paired with delete |
| NN-05 | Multi-DAW project file detection | Compete with DAW PM | DAW PM | **P3** | SPEC non-goal v1 |
| NN-06 | Google Drive / cloud backup | Off-machine sync | DAW PM | **P3** | SPEC non-goal v1 |
| NN-07 | Per-project todos and releases | Producer PM features | DAW PM | **P3** | Different product surface |
| NN-08 | AI similarity search on mixdowns | Find “sounds like” | Crate CLAP | **P3** | Heavy; optional far future |
| NN-09 | MCP / CLI export of archive index for agents | Automation | ableton-proj-mcp | **P2** | Fits Composer/agent workflow |
| NN-10 | Integrate **DAWFileKit** for marker XML only | Structured interchange | DAWFileKit | **P3** | Narrow use case |

---

## Hub tools backlog (outside archive SPEC)

Improvements inspired by peers for **BPM / converter / recorder / downloader / inbox** — not Cubase File Orga milestones.

| ID | Item | Peer | Priority |
|----|------|------|----------|
| HUB-01 | **Analyze BPM of inbox file or mixdown** (one-shot) | bpm-kit, spfk-tempo | **P1** |
| HUB-02 | Metronome / tuner module | Guitar-Utility | **P3** |
| HUB-03 | Batch “send mixdown to WAV converter” from archive detail | — | **P2** |
| HUB-04 | Recorder: visual level meter (ongoing polish) | AudioRecorderPavanKumar | **P1** |
| HUB-05 | Downloader: playlist / channel batch patterns | yt-dlp ecosystem | **P2** |

---

## What not to borrow (philosophy & scope)

| Peer feature | Why skip or adapt |
|--------------|------------------|
| CubaseTools **delete/move unused audio** | Violates read-only archive mission; offer **report-only** (NN-04) instead |
| CubaseTools **backup file deletion** | Same |
| DAW PM **multi-DAW** as v1 goal | SPEC non-goal; dilutes Cubase song-folder tuning |
| Crate **cloud sync / Stripe / AI** | Different product; native local-first hub |
| SampleSolution **web duplicate of library** | Storage doubling; not producer workflow |
| ableton-proj-mcp as **runtime dependency** | Keep optional export; don’t require MCP server for app |
| Electron + npm stack from MacBook reference | `docs/source-inventory.md` — port semantics only |

---

## Recommended phasing

### Phase 1 — Recall feels complete (P0)

1. **M1-08 / M1-09** — SQLite song index + incremental file watching (Foundation for everything else).
2. **M2-01, M2-03, M2-06** — Virtual title, editable notes, manual main preview.
3. **M3-01, M3-02, M3-07** — Smart shelves for recent bounces and CPR activity.
4. **M5-03** — Waveform hero + basic seek (Fruity Server / DAW PM player parity).

**Outcome:** Daily “find song → hear it → open CPR” matches Electron v1 intent without Electron.

### Phase 2 — Metadata & browse depth (P1)

1. **M2-05, M2-07, M2-08** — Collaborators, main CPR override, hide/ignore.
2. **M3-04–M3-06, M3-08** — Full search + shelf UX.
3. **M1-10, M5-N2** — Keyboard shortcuts and quick actions.
4. **M2-N1** — BPM from mixdown (bpm-kit or spfk-tempo SPM).
5. **M1-N2** — Archive health summary.

### Phase 3 — Creation & intelligence (P2)

1. **M4-*** — New song flow (if still desired).
2. **M5-01** — Collaborator suggestions.
3. **NN-01, NN-03, NN-04** — Read-only CPR plugin blurb, duplicates, missing audio report.
4. **NN-09** — CLI/agent export of index.

### Phase 4 — Strategic optional (P3)

Multi-DAW, cloud sync, todos/releases, cross-library plugin dashboard, AI search — only if product direction changes.

---

## Strengths to protect (don’t regress chasing peers)

1. **Song-folder + mixdown preview model** — Neither DAW PM nor CubaseTools optimizes “one card = one song + best bounce.”
2. **Preview maturity ladder + stem demotion** — Unique tuning; Crate/SampleWrangler don’t rank “main mix vs stem.”
3. **Read-only safety** — Marketed and tested; peer cleanup tools are the anti-pattern.
4. **Unified output inbox** — No peer combines archive recall + converter + recorder + downloader.
5. **Native Swift / single binary** — vs Electron (old Cubase app), Flutter, or Python+tkinter.
6. **Fixture-first + dry-run open** — Strong agent/CI story; most peers lack this discipline.

---

## Implementation hints (when picking items)

| Backlog theme | Suggested approach in this repo |
|---------------|----------------------------------|
| Persistence | New `NikoMusicCore` + AppCore store module; SQLite via GRDB or swift-sqlite; **no** Electron `better-sqlite3` |
| File watching | `FSEvents` wrapper in AppCore; debounced incremental rescan per root |
| Waveform | Accelerate/vDSP peaks + SwiftUI `Canvas`; or AVAssetReader sample buffers; cache peaks in DB |
| File BPM | SPM: [bpm-kit](https://github.com/hPerezz/bpm-kit) on main preview URL; show on detail only |
| CPR plugins read-only | Subprocess to CubaseTools CLI **or** port minimal parser into `NikoMusicCore` with strict read-only UI |
| Fuzzy search | Extend `MusicSearchMatcher`; optional import of small fuzzy lib if needed |

---

## References

### GitHub repositories

- [bandpassrecords/daw-project-manager](https://github.com/bandpassrecords/daw-project-manager)
- [schwifty00/CubaseTools](https://github.com/schwifty00/CubaseTools)
- [DreamerDeLy/fruity-server](https://github.com/DreamerDeLy/fruity-server)
- [closestfriend/ableton-proj-mcp](https://github.com/closestfriend/ableton-proj-mcp)
- [glenandrewbrown/logicx-analyzer](https://github.com/glenandrewbrown/logicx-analyzer)
- [orchetect/DAWFileKit](https://github.com/orchetect/DAWFileKit)
- [omeriko9/Cubase-Project-File-Reverse-Engineering](https://github.com/omeriko9/Cubase-Project-File-Reverse-Engineering)
- [lopadz/crate](https://github.com/lopadz/crate)
- [macvfx/p5ArchiveSearch](https://github.com/macvfx/p5ArchiveSearch)
- [thetheosopher/SampleWrangler](https://github.com/thetheosopher/SampleWrangler)
- [iversonianGremling/SampleSolution](https://github.com/iversonianGremling/SampleSolution)
- [ryanfrancesconi/spfk-tempo](https://github.com/ryanfrancesconi/spfk-tempo)
- [hPerezz/bpm-kit](https://github.com/hPerezz/bpm-kit)
- [Soham041201/Multi-music](https://github.com/Soham041201/Multi-music)
- [rebelonion/audio-share](https://github.com/rebelonion/audio-share)

### Internal docs

- `docs/reference/cubase-file-orga/SPEC.md` — milestone source of truth for archive behavior
- `docs/reference/cubase-file-orga/DESIGN_SYSTEM.md` — waveform hero, song card visuals
- `docs/source-inventory.md` — what to port vs not import from Electron reference
- `README.md` — shipped tool list
- `.ai/tasks/hub-polish-waves.json` — completed polish waves A–G

### Commercial reference

- [dBdone — preview Ableton projects](https://dbdone.com/blog/preview-ableton-projects-without-opening/)

---

## Document maintenance

When shipping archive features:

1. Update **Niko Music Hub baseline** table at top of § baseline.
2. Mark backlog IDs with commit SHA or phase number.
3. Re-run peer scan yearly or before a “v2 archive” milestone.

**Autonomous execution:** [`docs/goals/niko-archive-recall-autonomous.goals.md`](goals/niko-archive-recall-autonomous.goals.md) — ordered checkpoints CP-01–CP-18; use `/goal` + `cursor-goal` or `/gsd-autonomous --from 11 --to 18` (see goal file § How to run).
