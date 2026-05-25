# Cubase Song Archive Browser

## What This Is

A local-first macOS desktop app for a single professional Cubase producer to browse a large song archive as **songs**, not files. The user finds an idea quickly, hears the best preview immediately (chorus-biased when analysis exists), and opens the most recently modified relevant `.cpr` without folder hunting. The app is a recall layer on top of an existing Cubase archive — not a generic file manager, cloud tool, or DAW replacement.

## Core Value

**Find a song and hear the right preview in seconds, then open the right Cubase project.**

If tradeoffs arise, protect preview-first recall and song-first mental model over administrative features, generic file UX, or deep `.cpr` parsing.

## Current State (v1.0 shipped 2026-05-23)

Brownfield Electron app (Forge + Vite, React 19, TypeScript, Zustand, SQLite, Howler, chokidar). Main process owns fs/DB/scan/audio; renderer via typed `window.api` IPC only.

**Shipped in v1.0:** Canonical preview policy + title inference; chorus-biased playback with preload/marker UX; editorial resume browse + detail; full-text search and virtual metadata; deferred startup sync + incremental search index; `npm run check` + behavioral harnesses + `make:mac` packaging.

**Known tech debt (non-blocking):** Post-startup-sync UI refresh; optional human UAT on real archive; Nyquist VALIDATION.md not generated; code signing (PLAT-01) deferred to v2.

## Requirements

### Validated (v1.0)

- ✓ Archive roots, one-folder-one-song scan, watcher, incremental startup sync — v1.0
- ✓ Preview confidence ranking, manual/ignore, title inference, policy parity — v1.0
- ✓ Play preview, chorus-biased start, preload, marker, open latest CPR — v1.0
- ✓ Editorial browse shelves, resume split, song detail recall — v1.0
- ✓ Search, virtual title/aliases, collaborators, notes, CPR override — v1.0
- ✓ New song flow — v1.0
- ✓ Large-archive launch/sync/index performance — v1.0
- ✓ Ship gates (check, harnesses, macOS package, spec non-goals) — v1.0

### Active

- [ ] **v1.1+ planning** — run `/gsd-new-milestone` for next scope (see v2 ideas in archived requirements)

### Out of Scope

- Deep `.cpr` parsing as a core dependency — spec §12; folder/metadata only
- Cloud sync, multi-user collaboration, public sharing — spec §12
- Plugin-state inspection, full DAW-agnostic support — spec §12
- Heavy manual tagging; required BPM/key/genre entry — spec §12
- Generic sample/asset manager role — spec §12
- Renaming, moving, or deleting user files on disk — product rule (virtual org only)

## Context

**Authoritative product spec:** `docs/SPEC.md`

**Codebase map:** `.planning/codebase/`

**Milestone record:** `.planning/MILESTONES.md` · archives in `.planning/milestones/`

**User:** Single professional producer; local archive; Cubase on macOS.

## Constraints

- **Tech stack**: Locked per `docs/SPEC.md` and `AGENTS.md` — Electron, React 19, TS, Zustand, design-system tokens, better-sqlite3, Howler; no new npm deps without explicit approval
- **Process boundaries**: Renderer never touches fs/sqlite; all IO via IPC
- **Data safety**: Never rename/move/delete user files; virtual metadata only
- **Entity model**: One folder = one song; song is primary entity
- **Platform**: macOS-first (Cubase launch, template paths, ffmpeg probing)
- **Testing**: `npm run check` is gate; behavioral harnesses exist; Vitest deferred (PLAT-02)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Song-first, preview-first, local-first | Producer recall problem, not file admin | ✓ Good |
| Spec (`docs/SPEC.md`) is v1 contract | User milestone: ship spec | ✓ Good — v1.0 shipped |
| Auto preview/CPR with manual override | Low admin, user trust | ✓ Good |
| Centralize preview policy in main process | Parity across scan/sync/UI | ✓ Good — Phase 1 |
| Chorus-biased preview start | Hear best part first | ✓ Good — Phase 2 |
| Resume split UI + design-system tokens | Editorial browse | ✓ Good — Phase 3 |
| Defer startup sync after window | PERF-01 / SCAN-05 | ✓ Good — Phase 5–6 |
| Incremental search index on scan | PERF-02 | ✓ Good — Phase 6 |

## Next Milestone Goals

- Define v1.1+ via `/gsd-new-milestone` (candidates: PLAT-01 signing, PLAT-02 Vitest, startup-sync UI refresh fix, PROD-01/02 from v2 requirements)

---
*Last updated: 2026-05-23 after v1.0 milestone completion*
