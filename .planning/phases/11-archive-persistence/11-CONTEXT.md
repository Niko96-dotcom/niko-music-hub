# Phase 11: Archive persistence — Context

**Gathered:** 2026-05-30
**Status:** Ready for planning
**Mode:** Auto-generated (GSD v1.2 kickoff)

<domain>
## Phase Boundary

Persist the Cubase archive song index on disk and refresh it when archive roots change on the filesystem — without rescanning the entire tree on every app launch.

**Checkpoints:** CP-01 (SQLite), CP-02 (FSEvents) from `docs/goals/niko-archive-recall-autonomous.goals.md`

</domain>

<decisions>
## Implementation Decisions

- **Store:** SQLite via system `libsqlite3` in `NikoMusicCore` (no Electron `better-sqlite3`).
- **Snapshot model:** Single latest row: roots paths + JSON-encoded `[Song]` + `scannedAt` (matches existing `Song` Codable).
- **Cache validity:** Load cache only when persisted root paths match current settings roots (sorted compare).
- **Read-only:** Persistence never writes into user music folders.
- **Watcher:** FSEvents on archive roots; debounced full `scan()` (no per-folder incremental parser in this phase).
- **Tests:** Temp SQLite paths; fixture scans unchanged on disk.

### Claude's Discretion

Schema versioning, exact debounce interval, and whether to persist `skippedEntries` in v1.2 phase 11.

</decisions>

<code_context>
## Existing Code Insights

- `ArchiveBrowserViewModel` holds in-memory `songs` only; `scan()` replaces from `CubaseArchiveScanner`.
- `JSONOutputInboxStore` pattern for Application Support paths in `AppComposition`.
- `Song`, `ScanResult` already `Codable` in `NikoMusicCore`.

</code_context>

<specifics>
## Success Criteria (from ROADMAP)

1. Relaunch shows cached songs for unchanged roots before user taps Scan.
2. After scan, cache updates; `./script/ci.sh` green.
3. File changes under a root trigger debounced rescan without app restart.

</specifics>
