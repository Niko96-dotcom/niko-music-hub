# Goal: Niko Archive Recall — autonomous build (v1.2)

**Goal ID:** `niko-archive-recall-autonomous`  
**Source backlog:** [`docs/competitive-analysis-github-peers.md`](../competitive-analysis-github-peers.md)  
**Product spec:** [`docs/reference/cubase-file-orga/SPEC.md`](../reference/cubase-file-orga/SPEC.md)  
**Architecture:** [`AGENTS.md`](../../AGENTS.md) — native Swift, read-only archive, fixture-first tests

---

## How to run (pick one — no copy-paste chains)

### Option A — `/goal` in Cursor Command Code (recommended if you live in Cursor chat)

One kickoff, then keep saying **`/goal resume`** until the file shows all checkpoints `[x]` or you hit `budget_limited`.

```bash
cd /Users/niko/Documents/Niko-Music-Hub

cursor-goal clear 2>/dev/null || true

cursor-goal "Execute docs/goals/niko-archive-recall-autonomous.goals.md: work the first unchecked checkpoint (CP-##). One checkpoint per turn unless tiny. After each CP: mark [x], run gates, commit if green (user allows commits on this goal). Skip CP-19+ unless user un-skips P3 section. Read AGENTS.md and competitive-analysis for context." \
  --verify "./script/ci.sh && ./script/e2e_user_smoke.sh" \
  --max-turns 48
```

Then in chat: **`/goal resume`** (repeat until complete).

### Option B — GSD autonomous (recommended in Cursor)

**Prerequisite (once per Mac):**

```bash
npm install -g get-shit-done-cc
# verify:
gsd-sdk query roadmap.analyze
# or:
./script/gsd.sh query roadmap.analyze
```

Phases **11–18** are in [`.planning/ROADMAP.md`](../../.planning/ROADMAP.md). Phase **11 is done**.

In Cursor chat, send exactly:

```text
/gsd-autonomous --from 12 --to 18
```

Each phase runs discuss → plan → execute with artifacts under `.planning/`. No paste chains. Use **`/gsd-autonomous`**, not `gsd-sdk auto` (external runner).

### Option C — Hub polish style (one wave per chat)

Not ideal for 18 checkpoints; use A or B instead.

---

## Completion criteria (whole goal)

The goal is **COMPLETE** when:

1. Every checkpoint **CP-01 through CP-18** is `[x]` in this file.
2. `./script/ci.sh` and `./script/e2e_user_smoke.sh` pass on `main`.
3. Archive daily loop works: **persisted index**, **incremental updates**, **virtual title + notes + manual preview**, **recent shelves**, **waveform + seek**, **read-only** toward music roots.
4. P3 items (CP-19+) remain **skipped** unless explicitly enabled.

---

## Global rules (every checkpoint)

- **Read-only archive:** never rename/move/delete files under user music roots.
- **Tests:** fixture-first; extend `Fixtures/CubaseArchive/`; no `source.contains` string tests.
- **Gates:** `./script/ci.sh` after each CP; `./script/e2e_user_smoke.sh` before marking CP complete if UI/shell touched.
- **Commits:** coherent, green; message references CP-## and backlog IDs.
- **Do not import:** Electron/React/chokidar/better-sqlite3 from MacBook reference — port **behavior** in Swift only.
- **Out of scope unless CP says so:** multi-DAW, cloud sync, delete-unused-audio, AI search, App Store.

---

## Checkpoint index

| CP | Title | Backlog IDs | Status |
|----|--------|-------------|--------|
| [CP-01](#cp-01-archive-sqlite-persistence) | Archive SQLite persistence | M1-09 | [x] |
| [CP-02](#cp-02-incremental-scan-fsevents) | Incremental scan (FSEvents) | M1-08 | [x] |
| [CP-03](#cp-03-first-run-roots-ux) | First-run roots UX | M1-07 | [x] |
| [CP-04](#cp-04-virtual-title--aliases) | Virtual title + aliases | M2-01, M2-02 | [x] |
| [CP-05](#cp-05-editable-song-notes) | Editable song notes | M2-03 | [x] |
| [CP-06](#cp-06-manual-main-preview) | Manual main preview | M2-06, M5-07 | [x] |
| [CP-07](#cp-07-smart-shelves-recent) | Smart shelves (recent) | M3-01, M3-02, M3-07 | [x] |
| [CP-08](#cp-08-waveform-hero--seek) | Waveform hero + seek | M5-03, M5-04 | [x] |
| [CP-09](#cp-09-home-browse-shelves-ui) | Home browse + shelves UI | M3-08, M3-03 | [x] |
| [CP-10](#cp-10-collaborators-address-book) | Collaborators + address book | M2-05, M3-04, M3-06 | [x] |
| [CP-11](#cp-11-main-cpr-override-hide) | Main CPR override + hide | M2-07, M2-08 | [x] |
| [CP-12](#cp-12-keyboard-shortcuts-quick-actions) | Keyboard shortcuts | M1-10, M5-N2 | [x] |
| [CP-13](#cp-13-search-aliases-collaborators) | Search aliases + collaborators | M3-05, M3-06 | [x] |
| [CP-14](#cp-14-sort-filters-health-report) | Sort, filters, health report | M3-N1, M3-N2, M1-N2 | [x] |
| [CP-15](#cp-15-bpm-from-mixdown--hub) | BPM from mixdown + hub | M2-N1, HUB-01 | [x] |
| [CP-16](#cp-16-cpr-list-polish-confidence) | CPR list + confidence polish | M5-06, M5-02, M5-N1 | [x] |
| [CP-17](#cp-17-new-song-flow) | New song flow | M4-01–M4-04 | [x] |
| [CP-18](#cp-18-read-only-intelligence-export) | Read-only intelligence + export | M5-01, NN-01, NN-03, NN-04, NN-09 | [x] |
| [CP-19](#cp-19-p3--optional-skip-by-default) | P3 optional (skip) | NN-02, NN-05–08, HUB-02 | [ ] skip |

---

## CP-01: Archive SQLite persistence

**Backlog:** M1-09  
**Modules:** `NikoMusicCore`, `AppCore`, `FeatureArchiveBrowser`

**Build:**

- SQLite (or existing store pattern) under `~/Library/Application Support/Niko Music Hub/` for songs, CPR versions, preview candidates, scan timestamps.
- Load index on launch; merge scan results into DB instead of only in-memory arrays.
- App must **not** require full re-ingest on every launch (SPEC §7).

**Acceptance:**

- [ ] Second launch shows prior songs before rescan completes.
- [ ] Unit tests use temp DB paths; fixtures unchanged on disk.
- [ ] `./script/ci.sh` green.

**Verify:** `./script/ci.sh`

---

## CP-02: Incremental scan (FSEvents)

**Backlog:** M1-08  
**Depends:** CP-01  
**Modules:** `AppCore`, `FeatureArchiveBrowser`

**Build:**

- Watch archive roots with FSEvents (debounced).
- Incremental update affected song folders; manual **Rescan** still available.

**Acceptance:**

- [ ] Adding a mixdown under a fixture song updates that song without full-tree rescan (test with temp dir or fixture copy).
- [ ] No watcher leaks in tests (injectable watcher protocol).

**Verify:** `./script/ci.sh`

---

## CP-03: First-run roots UX

**Backlog:** M1-07  
**Modules:** `FeatureArchiveBrowser`, `NikoMusicHub`

**Build:**

- Dedicated first-run / empty-roots flow: pick active projects root (required), optional archive root (SPEC §5 screen inventory).
- Persist via existing `SettingsStore`.

**Acceptance:**

- [ ] Fresh settings show guided root picker, not dead-end empty list only.

**Verify:** `./script/ci.sh`

---

## CP-04: Virtual title + aliases

**Backlog:** M2-01, M2-02  
**Depends:** CP-01  
**Modules:** `NikoMusicCore`, `FeatureArchiveBrowser`

**Build:**

- `virtual_title` in DB; never rename disk folder.
- `aliases` JSON array; included in search index.

**Acceptance:**

- [ ] Edit display title in UI; folder path unchanged on disk.
- [ ] Search finds alias token.

**Verify:** `./script/ci.sh`

---

## CP-05: Editable song notes

**Backlog:** M2-03  
**Depends:** CP-01  
**Modules:** `NikoMusicCore`, `FeatureArchiveBrowser`

**Build:**

- App-owned song notes (distinct from read-only `notes.txt` sidecar); both searchable if SPEC requires.

**Acceptance:**

- [ ] Notes persist across relaunch; search matches note text.

**Verify:** `./script/ci.sh`

---

## CP-06: Manual main preview

**Backlog:** M2-06, M5-07  
**Depends:** CP-01  
**Modules:** `NikoMusicCore`, `FeatureArchiveBrowser`

**Build:**

- `preview_selection_mode`: auto | manual.
- UI to pick main preview, ignore candidate, revert to auto.
- List alternate previews on detail (extend existing partial UI).

**Acceptance:**

- [ ] Manual pick survives rescan when file still exists.
- [ ] Revert to auto restores ranker choice.

**Verify:** `./script/ci.sh`

---

## CP-07: Smart shelves (recent)

**Backlog:** M3-01, M3-02, M3-07  
**Depends:** CP-01  
**Modules:** `NikoMusicCore`, `FeatureArchiveBrowser`

**Build:**

- Shelves: **Recently Bounced**, **Recent CPR Activity** (SPEC §10 definitions).
- Filter/search support for “recent CPR changed”.

**Acceptance:**

- [ ] Fixture with dated CPR/mixdown files sorts into correct shelves.
- [ ] Tests document shelf rules.

**Verify:** `./script/ci.sh`

---

## CP-08: Waveform hero + seek

**Backlog:** M5-03, M5-04  
**Modules:** `FeatureArchiveBrowser`

**Build:**

- Waveform on song detail (see `DESIGN_SYSTEM.md`).
- Seek: ±5s buttons minimum; optional ±30s with modifier.

**Acceptance:**

- [ ] Waveform renders for fixture preview; playhead/scrub updates playback position.
- [ ] `./script/e2e_user_smoke.sh` still passes or updated deliberately.

**Verify:** `./script/ci.sh && ./script/e2e_user_smoke.sh`

---

## CP-09: Home browse + shelves UI

**Backlog:** M3-08, M3-03  
**Depends:** CP-07  
**Modules:** `FeatureArchiveBrowser`

**Build:**

- Browse-first home: sidebar shelves + song grid (not flat list only).
- **Has Stems** shelf when `has_stems` signal exists.

**Acceptance:**

- [ ] User can switch shelves without losing search context rules (document behavior).

**Verify:** `./script/ci.sh`

---

## CP-10: Collaborators + address book

**Backlog:** M2-05, M3-04, M3-06  
**Depends:** CP-01, CP-04  
**Modules:** `NikoMusicCore`, `FeatureArchiveBrowser`

**Build:**

- Collaborators table + song assignment.
- Shelf **By Collaborator**; search by collaborator name.

**Acceptance:**

- [ ] Assign collaborator to song; shelf and search find it.

**Verify:** `./script/ci.sh`

---

## CP-11: Main CPR override + hide

**Backlog:** M2-07, M2-08  
**Depends:** CP-01  
**Modules:** `NikoMusicCore`, `FeatureArchiveBrowser`

**Build:**

- Manual main `.cpr` (auto/manual like preview).
- Hide song / hide CPR version / hide preview candidate from normal browse.

**Acceptance:**

- [ ] Hidden song absent from default list; reveal path exists in settings or filter.

**Verify:** `./script/ci.sh`

---

## CP-12: Keyboard shortcuts + quick actions

**Backlog:** M1-10, M5-N2  
**Modules:** `FeatureArchiveBrowser`, `NikoMusicHub`

**Build:**

- Shortcuts: Preview, Open CPR, Open folder, Detail (map from DAW PM P/O/D/F pattern).
- Clear labels: Open in Cubase vs Reveal in Finder.

**Acceptance:**

- [ ] Shortcuts documented in README or archive help; work when archive focused.

**Verify:** `./script/ci.sh`

---

## CP-13: Search aliases + collaborators

**Backlog:** M3-05, M3-06  
**Depends:** CP-04, CP-10  
**Modules:** `NikoMusicCore`

**Build:**

- Extend `MusicSearchMatcher` for virtual title + aliases + collaborator names.

**Acceptance:**

- [ ] Tests for each field class from SPEC §10.

**Verify:** `./script/ci.sh`

---

## CP-14: Sort, filters, health report

**Backlog:** M3-N1, M3-N2, M1-N2  
**Depends:** CP-07, CP-09  
**Modules:** `FeatureArchiveBrowser`, `NikoMusicCore`

**Build:**

- Sort: recent bounce, recent CPR, title A–Z.
- Filter chips: stems / no preview / has warnings.
- **Archive health** summary: counts of songs missing preview, missing CPR, with warnings.

**Acceptance:**

- [ ] Health panel or settings diagnostic shows counts; read-only.

**Verify:** `./script/ci.sh`

---

## CP-15: BPM from mixdown + hub

**Backlog:** M2-N1, HUB-01  
**Modules:** `FeatureArchiveBrowser`, `FeatureBPMTapper` or `AppCore`, optional SPM `bpm-kit`

**Build:**

- Estimate BPM from main preview file (display only).
- Optional: analyze file from output inbox (one-shot).

**Acceptance:**

- [ ] BPM shown on detail for fixture with known tempo OR test uses synthetic audio fixture.
- [ ] No network; fails gracefully on short/silent files.

**Verify:** `./script/ci.sh`

---

## CP-16: CPR list + confidence polish

**Backlog:** M5-06, M5-02, M5-N1  
**Depends:** CP-06, CP-08  
**Modules:** `FeatureArchiveBrowser`, `NikoMusicCore`

**Build:**

- Full `.cpr` version list on detail with dates/notes.
- Compact waveform on song cards (optional if perf ok).
- Tune ranker only with fixture tests (Anne Monsters etc. still pass).

**Acceptance:**

- [ ] All CPR versions listed; main indicated.
- [ ] Existing preview ranking tests green.

**Verify:** `./script/ci.sh`

---

## CP-17: New song flow

**Backlog:** M4-01, M4-02, M4-03, M4-04  
**Depends:** CP-01, CP-10  
**Modules:** `FeatureArchiveBrowser`, `NikoMusicHub`

**Build:**

- New Song modal: name, collaborators, template path, note.
- Create folder + `Mixdown` / `Stems`; register in index; open Cubase (or dry-run in CI).

**Acceptance:**

- [ ] Creates folder under chosen root in test temp dir; does not touch real user archives in CI.
- [ ] `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` for automation open.

**Verify:** `./script/ci.sh`

---

## CP-18: Read-only intelligence + export

**Backlog:** M5-01, NN-01, NN-03, NN-04, NN-09  
**Depends:** CP-10  
**Modules:** `NikoMusicCore`, `FeatureArchiveBrowser`, optional CLI target

**Build:**

- Collaborator suggestions review UI (yes/no only).
- Read-only CPR plugin summary (subprocess CubaseTools CLI or minimal parser) — **no delete**.
- Duplicate song hints (heuristic); missing audio report (read-only).
- Export index JSON for agents (`swift run` or menu).

**Acceptance:**

- [ ] No destructive cleanup actions in UI.
- [ ] Export produces valid JSON from fixture scan.

**Verify:** `./script/ci.sh`

---

## CP-19: P3 — optional (skip by default)

**Backlog:** NN-02, NN-05, NN-06, NN-07, NN-08, NN-10, HUB-02, HUB-03, HUB-05, M2-N2, M2-N3, M3-09, M5-05, M1-N1  

**Do not implement** unless user removes `skip` and explicitly starts CP-19.

Multi-DAW, cloud sync, todos/releases, AI search, cross-library plugin dashboard, metronome/tuner, etc.

---

## GSD phase map (for `/gsd-autonomous`)

| Phase | ROADMAP title | Checkpoints |
|-------|----------------|-------------|
| 11 | Archive persistence | CP-01, CP-02 |
| 12 | Metadata core | CP-03, CP-04, CP-05, CP-06 |
| 13 | Recent shelves | CP-07 |
| 14 | Waveform player | CP-08 |
| 15 | Browse + collaborators | CP-09, CP-10, CP-11, CP-12, CP-13 |
| 16 | Filters, BPM, polish | CP-14, CP-15, CP-16 |
| 17 | New song flow | CP-17 |
| 18 | Read-only intelligence | CP-18 |

---

## Progress log

| Date | CP | Commit | Notes |
|------|-----|--------|-------|
| | | | |
