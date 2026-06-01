# Architecture

Niko Music Hub is a native macOS Swift package with a small app executable and feature modules registered through a shared tool boundary. The archive browser uses the same composition model as the BPM tapper, converter, recorder, downloader, and output inbox.

## Principles

| Principle | Meaning |
| --- | --- |
| Native app | Swift 6.x, SwiftUI, and focused AppKit interop for macOS handoff surfaces. |
| Local first | Archive roots, output folders, and helper tools stay on the user's Mac. |
| Read-only archives | Real Cubase/music folders are never renamed, moved, deleted, or rewritten. |
| Pure domain core | Archive scanning, ranking, search, diagnostics, and safety live outside UI code. |
| Fixture-first tests | Public generated fixtures prove behavior without private music files. |

## Module Graph

```text
NikoMusicHub
├── AppCore
├── NikoMusicCore
├── FeatureArchiveBrowser
├── FeatureBPMTapper
├── FeatureAudioConverter
├── FeatureAudioRecorder
└── FeatureDownloader
```

## Module Responsibilities

| Module | Responsibilities | Depends on |
| --- | --- | --- |
| `NikoMusicCore` | Song model, root policy, scanner, CPR detection, preview candidate detection, preview ranking, search, diagnostics export, path safety, opener policy. | Foundation |
| `AppCore` | `ToolFeature`, `ToolRegistry`, settings, jobs, output inbox, file actions, diagnostics, shared SwiftUI components. | SwiftUI, Foundation |
| `FeatureArchiveBrowser` | Root selection, scan/search/detail UI, preview player wrapper, diagnostics panel, dry-run smoke path. | `AppCore`, `NikoMusicCore`, AVFoundation/AppKit where needed |
| `FeatureBPMTapper` | Tap timing, BPM estimation, half/double adjustment, history, clipboard handoff. | `AppCore` |
| `FeatureAudioConverter` | Audio intake scanning, native conversion, optional FFmpeg fallback, WAV verification, inbox handoff. | `AppCore`, AVFoundation |
| `FeatureAudioRecorder` | CoreAudio process tap session, recorder use case, WAV writer, permission/error UI. | `AppCore`, `FeatureAudioConverter`, AVFoundation/CoreAudio |
| `FeatureDownloader` | `yt-dlp` health, download command building, progress parsing, output handoff. | `AppCore` |
| `NikoMusicHub` | App entrypoint, menu, feature registration, smoke command dispatch. | Feature modules |

## Archive Data Flow

```text
Selected roots
  -> CubaseArchiveScanner
  -> Song + ProjectVersion + PreviewCandidate
  -> PreviewConfidenceRanker
  -> MusicSearchIndex
  -> ArchiveBrowserViewModel
  -> SwiftUI browse, detail, preview, diagnostics, open/reveal
```

## Archive Safety

The archive browser keeps a strict split between read paths and write paths.

| Operation | Archive root | Output folder | App support |
| --- | --- | --- | --- |
| Scan folders | Read | No access | No access |
| Read file metadata | Read | No access | No access |
| Read WAV headers | Read | No access | No access |
| Open/reveal latest CPR | Handoff only | No access | Optional dry-run log |
| Diagnostics export | Read source data only | Write export outside archive | Write app-owned metadata |
| Converter/recorder/downloader output | No access | Write | Write inbox metadata |

## Preview Ranking

Preview ranking is deterministic and explainable. The current ranker scores candidates using:

1. Detected role, such as full mix, master, instrumental, stem-like, or unknown.
2. Folder role, especially `Mixdown`.
3. Filename signals, including positive mix/bounce/master tokens and negative stem/temp/reference tokens.
4. Parsed version numbers as tiebreaks.
5. Extension preference as tiebreaks.
6. WAV duration plausibility and duration tiebreaks.
7. Recency.

The diagnostics panel and exported support summaries expose the same ranking signals so user-facing behavior can be audited from fixtures.

## Settings And App Data

| Data | Location |
| --- | --- |
| Archive roots | App settings, stored under Application Support/UserDefaults. |
| Output folder | App settings. Default display path is `~/Music/Niko Music Hub/Inbox`. |
| Output inbox metadata | App-owned JSON store under Application Support. |
| Generated media | User-selected output folder. |
| Archive files | User-selected archive roots, read-only. |

## Verification Strategy

| Layer | Gate |
| --- | --- |
| Build | `swift build` |
| Unit/integration tests | `swift test` through `./script/ci.sh` |
| Fixture self-test | `swift run NikoMusicCoreSelfTest` |
| User-flow smoke | `./script/e2e_user_smoke.sh` |
| Bundle verification | `./script/build_and_run.sh --verify` |

Host-only recorder tests are source-controlled but skipped in the default CI script because CoreAudio capture depends on machine hardware and macOS privacy state.
