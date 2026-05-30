# Phase 11 — Verification

**Status:** Implementation complete (automated). Human spot-check optional.

## Automated

- [x] `SQLiteArchiveIndexStoreTests` — save/load roundtrip, empty load, root matching
- [x] `ArchiveBrowserViewModelTests.testLoadsCachedIndexWhenRootsMatch`
- [x] `./script/ci.sh` (run at phase close)

## Human (optional)

- [ ] Relaunch app with existing archive roots — songs appear before Scan
- [ ] Add mixdown under a song folder — list refreshes within ~2s without manual Scan

## Artifacts

- `NikoMusicCore/Persistence/SQLiteArchiveIndexStore.swift`
- `AppCore/Archive/FSEventsArchiveRootWatcher.swift`
- Plans: `11-01-PLAN.md`, `11-02-PLAN.md`
