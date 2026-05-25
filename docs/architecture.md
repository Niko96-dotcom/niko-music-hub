# Architecture — Niko Music Hub

Last verified: 2026-05-25

## Principles

1. **Seed, don't rewrite** — `OutsideCubaseHub` Swift spine stays; add modules, then rename.
2. **Port behavior, not stacks** — Cubase archive logic from `docs/reference/cubase-file-orga/SPEC.md`, never Electron/npm.
3. **Feature symmetry** — Archive browser registers via the same `ToolFeature` protocol as BPM/converter/recorder/downloader.
4. **Pure core** — `NikoMusicCore` has no SwiftUI/AppKit imports.
5. **Read-only archives** — Domain layer enforces path safety before any open/reveal.

## Target module graph

```text
NikoMusicHub (executable)
├── AppComposition
├── AppShell/                    # existing 3-column shell
├── FeatureArchiveBrowser      # NEW — SwiftUI browse/search/detail/play
├── FeatureBPMTapper             # unchanged role
├── FeatureAudioConverter
├── FeatureAudioRecorder
├── FeatureDownloader
├── AppCore                      # ToolFeature, registry, jobs, inbox, settings
└── NikoMusicCore                # NEW — scan, rank, search, open safety
    └── NikoMusicCoreSelfTest    # NEW — CLI fixture + real-root smoke
```

## Layer responsibilities

### `NikoMusicCore` (pure Swift)

No UI. Owns archive domain and safety.

| Area | Types / services | Notes |
|------|------------------|-------|
| Domain | `Song`, `ProjectVersion` (CPR), `PreviewCandidate`, `MusicRoot`, `ScanResult` | App-owned model; no SQLite requirement in v0.1 — in-memory + JSON cache OK |
| Scanning | `CubaseArchiveScanner`, `CPRVersionDetector`, `PreviewCandidateDetector`, `SongTitleResolver` | One child folder = one song; recurse for `.cpr` and audio |
| Search | `MusicSearchIndex` | In-memory index; fields per spec §10 |
| Opening | `MusicItemOpener` | Reveal/open latest CPR; supports `dryRun: Bool` for tests |
| Safety | `PathSafety`, `ReadOnlyArchivePolicy` | Reject paths outside declared roots; block writes under archive roots |

Dependency rule: `NikoMusicCore` depends only on Foundation (and possibly AVFoundation later for duration — optional v0.1).

### `AppCore` (existing — preserve)

Keep and extend minimally:

- `ToolFeature` / `ToolRegistry` / `ToolContext`
- `JobRunner`, `OutputInbox`, `SettingsStore`
- Shared components (`ToolHeaderBlock`, `StandardErrorCard`, etc.)

Do **not** fold archive scanning into `AppCore`; inject a `ArchiveService` or store protocol from `FeatureArchiveBrowser` if needed.

### `FeatureArchiveBrowser` (new)

SwiftUI feature module.

| File (planned) | Role |
|----------------|------|
| `ArchiveBrowserFeature.swift` | `ToolFeature` conformance, metadata id `archive-browser` |
| `ArchiveBrowserView.swift` | Root browse + search |
| `ArchiveBrowserViewModel.swift` | Scan state, selection, search query |
| `SongDetailView.swift` | CPR list, previews, actions |
| `PreviewPlayerView.swift` | AVPlayer wrapper; v0.1 simple play/pause |
| `ArchiveDesignTokens.swift` | SwiftUI colors/type from DESIGN_SYSTEM |

Depends on: `AppCore`, `NikoMusicCore`.

### `NikoMusicHub` (rename from `OutsideCubaseHub`)

- `NikoMusicHubApp.swift` — `@main`, activation policy
- `AppComposition.swift` — register all features; archive first in list
- Update Application Support subdirectory name
- Update `script/build_and_run.sh` app name and bundle id

## Composition wiring

```swift
// AppComposition.make() — target order
let features: [any ToolFeature] = [
    ArchiveBrowserFeature(),   // default home
    BPMTapperFeature(),
    AudioConverterFeature(),
    AudioRecorderFeature(),
    DownloaderFeature(),
    // DevToolFeature() — optional, last or removed from default
]
```

`AppShellView` default selection: `archive-browser` when present (replace today’s `wav-converter` default).

`FeatureArchiveBrowser` owns an internal `NavigationSplitView` (or equivalent) for song list → detail inside the center column; the outer shell stays 3-column.

`ToolContext` extension (v0.1): add optional `archiveSettings: ArchiveSettingsStore` or pass roots via `UserDefaults`/settings key — keep interface small.

## Data flow

```text
User selects roots (FeatureArchiveBrowser)
        ↓
CubaseArchiveScanner (NikoMusicCore) — read-only filesystem walk
        ↓
Song[] + PreviewCandidate[] + ProjectVersion[]
        ↓
Preview ranker → main preview per song
        ↓
MusicSearchIndex.build(songs)
        ↓
SwiftUI list/cards ← query filter
        ↓
User: Play preview → AVPlayer(url)
User: Open latest → MusicItemOpener → NSWorkspace / dry-run log
```

## Metadata persistence (v0.1)

Electron used SQLite. Swift v0.1:

- **In-memory** scan results per session only
- **No** `archive-cache.json` in v0.1 (deferred — avoids persistence scope creep)
- Manual rescan clears/rebuilds in-memory index

Milestone 2+ can add virtual titles, collaborator overrides — same store, schema versioning later.

## Preview ranking (port from spec)

Implement `PreviewConfidenceRanker` with SPEC §8 steps 1–6 for v0.2 preview picking:

1. Role confidence (full mix > instrumental > stems)
2. Location (`Mixdown` folder boost)
3. Filename semantics (positive/negative tokens)
4. Parsed version number from filename (tiebreak + score bump)
5. Extension preference (`wav` > `flac` > `aiff` > `m4a` > `mp3`)
6. Duration plausibility (penalize very short; boost typical song length from WAV header)
7. Recency (modification date, small tiebreak)

Defer: chorus/loudness preview start, manual overrides.

Output: `mainPreviewCandidateID` per song + `confidenceReasons[]` for debug UI.

## CPR selection

`CPRVersionDetector`:

- Collect all `*.cpr` under song folder (exclude `.bak` from main list by default)
- `latestCPR` = argmax `contentModificationDate`
- Expose full sorted list on detail view

## Search index

`MusicSearchIndex` indexes per spec §10 searchable fields:

- Display title (resolved from folder name in v0.1)
- Original folder name
- CPR filenames
- Preview filenames

v0.1 skips: aliases, collaborator names, song notes (no metadata layer yet).

## Safety architecture

```swift
ReadOnlyArchivePolicy.enforce {
  // allowed: read, enumerate, metadata stat
  // denied: write, delete, move, create under archiveRoot
}
PathSafety.resolve(userPath, allowedRoots: settings.roots) -> URL?
```

`MusicItemOpener.openLatestCPR(song, dryRun:)`:

- `dryRun == true`: append to diagnostics/log file; no `NSWorkspace.open`
- `dryRun == false`: `NSWorkspace.shared.open(cprURL)` or reveal-in-Finder variant for E2E

## Testing architecture

| Layer | Test home |
|-------|-----------|
| Core scanner/ranker/search | `Tests/NikoMusicCoreTests/` + fixtures under `Fixtures/CubaseArchive/` |
| Feature VM/UI logic | `Tests/FeatureArchiveBrowserTests/` |
| Registry integration | extend `AppCoreTests/FeatureRegistryTests` |
| CLI smoke | `NikoMusicCoreSelfTest` |
| User E2E | `script/e2e_user_smoke.sh` + env vars `NIKO_MUSIC_HUB_FIXTURE_ROOT`, `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` |

### Fixture layout (planned)

```text
Fixtures/CubaseArchive/
  Neon Hook/
    Neon Hook.cpr
    Mixdown/Neon Hook v3.wav
    Ideas/Neon Hook topline.mid
  Broken Folder Example/
    notes.txt          # no CPR — scan warning
  Second Song/
    ...
```

## Rename map (executor slice 5)

| From | To |
|------|-----|
| Package `OutsideCubaseHub` | `NikoMusicHub` |
| Target `OutsideCubaseHub` | `NikoMusicHub` |
| `OutsideCubaseHubApp` | `NikoMusicHubApp` |
| `dist/OutsideCubaseHub.app` | `dist/NikoMusicHub.app` |
| Bundle id `local.outside-cubase-hub.app` | `local.niko-music-hub.app` |
| App Support `Outside Cubase Hub` | `Niko Music Hub` |

Use mechanical rename + test run; avoid drive-by refactors in feature modules.

## What stays unchanged

- Feature module boundaries for BPM/converter/recorder/downloader
- `JobRunner` / output inbox handoff patterns
- FFmpeg / yt-dlp / CoreAudio integration code paths
- CI skip list for recorder hardware tests

## Anti-patterns (reject in review)

- Importing React/Electron types or copying TS scanner code verbatim
- SQLite + chokidar as v0.1 requirements
- Single god-module `AppCore+Archive`
- Writing scan caches into music folders
- Hermes parallel workers or Locus env dependencies
