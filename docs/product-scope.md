# Product Scope — Niko Music Hub v0.1

Last verified: 2026-05-25

## Product definition

**Niko Music Hub** is one native macOS SwiftUI app that combines:

1. **Cubase archive browser** — browse songs (not files), hear the best preview, open the latest `.cpr`.
2. **Outside-Cubase tools** — BPM tapper, WAV converter, system-audio recorder, downloader, shared output inbox.

The user problem: recall a song idea in seconds without folder hunting. The app is a **read-only recall layer** on top of an existing Cubase archive, not a file manager or DAW replacement.

## v0.1 — Must ship

### App identity

- Native `.app` named **Niko Music Hub**
- Swift 6.x, SwiftUI + AppKit interop where needed
- Launches from `dist/NikoMusicHub.app` (or equivalent after rename)

### Preserved outside-Cubase tools

All existing modules keep working with tests green after rename:

| Tool | Acceptance |
|------|------------|
| BPM Tapper | Tap, estimate, history, clipboard |
| WAV Converter | Batch convert, FFmpeg health, output handoff to inbox |
| Audio Recorder | Permission UX, shell; host-only capture tests remain manual |
| Downloader | yt-dlp jobs, progress, inbox handoff |
| Output Inbox | Cross-tool handoff, reveal in Finder |
| Dev Tool | Optional; may stay behind default selection |

### New archive browser (Milestone 1 from Cubase spec)

Port **behavior**, not Electron code.

| Capability | v0.1 acceptance |
|------------|-----------------|
| Opt-in root selection | User picks one or more scan roots; persisted in app settings |
| Scan | Fixture archive scans to song entities; one immediate child folder = one song |
| CPR detection | All `.cpr` under song folder; latest = max modification date (not version number) |
| Preview detection | Supported audio in Mixdown/root/etc.; **v0.1 ranker subset** (role + folder + filename tokens + recency — not duration/chorus heuristics) |
| Main preview | One ranked preview per song; playable in UI |
| Search | Title, folder name, preview filename, CPR filename (fixture-backed) |
| Browse | Song list/cards with waveform placeholder or simple bar |
| Detail | Full CPR version list, preview candidates, open/reveal actions |
| Open latest CPR | Opens or reveals newest `.cpr`; **dry-run mode** for fixtures/E2E logs path without launching Cubase |

### Testing gates

| Gate | Requirement |
|------|-------------|
| `./script/ci.sh` | `swift build`, `swift test` (with existing recorder skips), `swift run NikoMusicCoreSelfTest` on fixtures |
| Fixture unit tests | Scanner, CPR detector, preview ranker, search index — no real archive required |
| `./script/e2e_user_smoke.sh` | Build app, launch with fixture root + dry-run open, search "Neon Hook", verify preview + CPR visible, trigger open, assert dry-run log |
| Real archive smoke | `NikoMusicCoreSelfTest --real-root <path> --read-only` — counts only, zero writes under music root |

### Safety (non-negotiable)

- **Never** rename, move, delete, or rewrite files under user music/archive roots
- Scanner and opener are read-only toward archive paths
- App-owned metadata lives under Application Support / test temp only
- New song creation, file watcher, SQLite Electron DB — **out of v0.1**

## v0.1 — Explicit non-goals

| Non-goal | Reason |
|----------|--------|
| Deep `.cpr` parsing | Spec: folder/metadata only |
| Cubase plugin/VST integration | Out of recall scope |
| Moving/renaming/deleting real files | Product safety rule |
| Cloud sync / multi-user | Spec §12 |
| Public signing/notarization | Private repo phase |
| AI generation in app | Not requested |
| Electron/React/TS/Python in product | Architecture rule |
| Migrating Electron SQLite DB | Fresh Swift metadata model |
| Collaborator suggestion UI | Milestone 2+ |
| Virtual rename / manual preview override | Milestone 2+ |
| New song creation flow | Milestone 4 |
| Smart shelves (Recently Bounced, etc.) | Milestone 3 — optional stub OK, not required |
| Chorus-biased preview analysis | v1 Electron had it; v0.1 may start at t=0 |
| chokidar live watcher | Full scan + manual rescan sufficient for v0.1 |
| GitHub Actions | Local gates only |

## UX intent (from design reference)

Translate `docs/reference/cubase-file-orga/DESIGN_SYSTEM.md` into SwiftUI:

- Dark, soft, spacious, editorial — not spreadsheet/Finder
- Waveform as hero on cards and detail (can be simplified bar in v0.1)
- Archive browser feels like **home**; outside tools remain sidebar tools in the same shell

Default shell strategy for v0.1:

- Register `archive-browser` as first/default `ToolFeature`
- Keep existing 3-column tool shell (sidebar | tool | inbox) — **do not** rewrite to Automation Health single-window layout in v0.1
- Archive feature uses the **center column only**, with nested browse/detail navigation inside `FeatureArchiveBrowser`
- Optional JSON metadata cache is **post-v0.1**; v0.1 uses in-memory scan results

## Definition of done (v0.1)

- [ ] App named Niko Music Hub builds and launches
- [ ] All pre-existing outside-tool tests pass (minus documented CI skips)
- [ ] `NikoMusicCore` fixture tests pass
- [ ] Archive browser wired and usable on fixture root
- [ ] `./script/ci.sh` green
- [ ] `./script/e2e_user_smoke.sh` green
- [ ] Real-root read-only smoke documented and runnable
- [ ] No Locus paths touched
- [ ] No real music files modified
