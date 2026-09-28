# Architecture — Niko Music Hub

Last verified: 2026-09-27

## Principles

1. **Maintain the shipped product** — extend and harden existing modules; no re-bootstrapping.
2. **Native Swift port** — Cubase archive behavior from `reference/cubase-file-orga/`, never Electron/npm.
3. **Feature symmetry** — Archive browser registers via the same `ToolFeature` protocol as BPM/converter/recorder/downloader.
4. **Pure core** — `NikoMusicCore` has no SwiftUI/AppKit imports.
5. **Local-first, read-only archives** — domain path safety before any open/reveal; no music-file mutation outside an explicit Vault transfer.

## Current module graph

```text
NikoMusicHub (executable)
├── AppComposition / AppShell
├── FeatureArchiveBrowser      # archive browse/search/detail/play + Project Vault UI
├── FeatureBPMTapper
├── FeatureAudioConverter
├── FeatureAudioRecorder
├── FeatureDownloader
├── FeatureStemSeparation      # narrow exception below
├── AppUpdates                 # isolated Sparkle updater
├── AppCore                    # shared shell kit + Project Vault runtime (see below)
└── NikoMusicCore              # scan, rank, search, open safety, persistence, Vault engines
```

- `FeatureArchiveBrowser` depends on `AppCore` and `NikoMusicCore` only.
- Feature modules stay independent except the documented Stem Separation → Downloader exception.
- Guarded ([ADR 020](decisions/020-module-boundary-checks.md)): the product builds pass `--explicit-target-dependency-import-check error`, and `ModuleBoundarySourceTests` pins Core's framework imports and the feature→feature edges. A new edge changes this document and that test in the same commit.
- Composition: [`AppComposition`](../Sources/NikoMusicHub/AppComposition.swift) registers all features; the archive is the default home. Shared tool wiring flows through [`ToolContext`](../Sources/AppCore/Services/ToolContext.swift).

## Existing feature dependency: Stem Separation → Downloader

Verified 2026-09-19: `Package.swift` explicitly makes `FeatureStemSeparation`
depend on `FeatureDownloader`. This is a narrow exception to feature independence:
the YouTube input adapter in
[`YouTubeStemSeparationWorkflow.swift`](../Sources/FeatureStemSeparation/YouTubeStemSeparationWorkflow.swift)
uses `DownloaderUseCase` and its request types to obtain an audio file. The
composition in `StemSeparationFeature` supplies the existing yt-dlp implementation
and health checker. The separation workflow itself depends on
`YouTubeAudioDownloading`; it does not depend on the downloader view or view model.

Keep this dependency explicit while both features share the download behavior,
including retries, output containment and no-overwrite handling. Changes to that
behavior must also run the Stem Separation workflow tests. Extracting a shared
service module is deferred until another consumer or an actual boundary problem
justifies the migration; duplicating the downloader would create two safety paths.

## Layer responsibilities

### `NikoMusicCore` (pure Swift)

Archive domain and safety. No SwiftUI/AppKit.

- Domain: `Song`, `ProjectVersion`, `PreviewCandidate`, `StoredMusicRoot`, `ScanResult`.
- Scanning: `CubaseArchiveScanner`, `CPRVersionDetector`, `PreviewCandidateDetector`, `SongTitleResolver`.
- Search: `MusicSearchIndex`; ranking: `PreviewConfidenceRanker`.
- Opening: `MusicItemOpener` with dry-run support for tests.
- Safety: `PathSafety`, `ReadOnlyArchivePolicy`.
- Catalog helpers: `SongCatalogDeduplicator`, `ArchiveMetadataMerger`.
- `Vault/`: the Project Vault engines (`LocalVaultTransferEngine`, `LocalVaultRestoreEngine`, `VaultManifest`,
  archive storage providers, the transfer state machine and automation rules).
- `Persistence/`: the SQLite stores (`SQLiteArchiveDatabase` and the index, metadata, collaborator, catalog and
  Vault transfer stores).
- `Browse/` (filters, sort, smart shelves, health report), `Intelligence/` (archive intelligence, index export),
  `Preview/` (mixdown BPM/key estimation, hook locator).

### `AppCore` (shared)

`AppCore` holds two things: the shared shell kit, and (until it gets its own target) the Project Vault runtime.

- Shell kit: `ToolFeature` / `ToolRegistry` / `ToolContext`, `JobRunner`, the Output Inbox (`OutputInbox/`),
  `SettingsStore` (`UserDefaultsSettingsStore`), diagnostics, `HelperTools/` (helper locator, installer, Set Up
  model), `Archive/` (FSEvents archive-root watcher), `Audio/` (WAV output spec and verification), `QuickAccess/`
  (router, menu bar model), `Navigation/` (`HubNavigationHistory`).
- Shell jobs and quit: `ShellJobStatusCenter`, `CancelCopy`, `HubTerminationCoordinator` (see
  [Running work and quit](#running-work-and-quit)).
- Project Vault runtime: `LiveProjectVaultRuntime`, `ProjectVaultOperating`, and admission/capacity/activity probes; it uses the transfer/catalog SQLite stores owned by `NikoMusicCore/Persistence`.
- Shared UI: `ToolHeaderBlock`, `HubInspectorPage`, hub design tokens (see `docs/design-contract.md`).

### `FeatureArchiveBrowser` (SwiftUI feature)

- [`ArchiveBrowserFeature.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserFeature.swift): `ToolFeature` conformance (`archive-browser`).
- [`ArchiveBrowserViewModel.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel.swift): roots, browse, selection, scan host, and integration with metadata/Vault owners.
- Vault operation extensions: `+ProjectVaultQueue.swift`, `+ProjectVaultArchive.swift`, `+ProjectVault.swift`, `+ProjectVaultActions.swift`, `+ProjectVaultRestore.swift`, `+ProjectVaultRecovery.swift`, `+Metadata.swift` (Done revoke), `+Scan.swift` (root-bound clears).
- Coordinators: [`ArchiveScanOrchestrator`](../Sources/FeatureArchiveBrowser/ArchiveScanOrchestrator.swift), [`ArchiveCatalogCoordinator`](../Sources/FeatureArchiveBrowser/ArchiveCatalogCoordinator.swift), [`ProjectVaultOperationCoordinator`](../Sources/FeatureArchiveBrowser/ProjectVaultOperationCoordinator.swift), [`ArchiveMetadataEditingCoordinator`](../Sources/FeatureArchiveBrowser/ArchiveMetadataEditingCoordinator.swift) (song-metadata mutation ordering), [`ArchiveVaultObservation`](../Sources/FeatureArchiveBrowser/ArchiveVaultObservation.swift) (Vault observation/presentation).
- Views: `ArchiveBrowserView`, `SongDetailView`, board/list/analytics subviews (see `docs/design-contract.md`; do not regress).

## Persistence, services, composition

- Settings: `UserDefaultsSettingsStore` owns `AppSettings` (music roots, vault bindings, Keep Local pins). Vault presentation reads settings only at explicit boundaries (`refreshProjectVaultPresentationContext`).
- Archive persistence (production `AppComposition.swift:74-126`): one shared `SQLiteArchiveDatabase` backs `SQLiteArchiveIndexStore` (`ArchiveIndexStoring`), `SQLiteSongUserMetadataStore` (`SongUserMetadataStoring`), `SQLiteCollaboratorStore` (`CollaboratorStoring`), `SQLiteProjectCatalogStore`, and `SQLiteVaultTransferStore`. SQLite stores live in `NikoMusicCore/Persistence`; the Vault runtime (`LiveProjectVaultRuntime`, `ProjectVaultOperating`) lives in `AppCore`. Scans reconcile through `ArchiveCatalogCoordinator`.
- Song metadata: `SongUserMetadataStoring` SQLite rows (titles, aliases, notes, workflow status, collaborators); per-song merge/commit path with corrupt-row gating.
- Vault transfers: `SQLiteVaultTransferStore` over `SQLiteArchiveDatabase` (transfer journal is authoritative for phases/recovery).
- Vault catalog: `SQLiteProjectCatalogStore` (project records, locations, identity reviews).
- Runtime composition: `LiveProjectVaultRuntime` is built with the settings, transfer and catalog stores and a project opener; storage providers and activity/capacity probes use their production defaults. It is injected into the archive view model as `ProjectVaultOperating`.
- App composition builds one `HubNavigationHistory`, one settings store suite, job center, diagnostics, and file actions. It builds two `ToolContext` values over those same services: one for the archive view model, built before the registry, and a final one for the shell and features that also carries a registry-failure persistence issue.

## Project Vault operation ownership

- [`ProjectVaultOperationCoordinator`](../Sources/FeatureArchiveBrowser/ProjectVaultOperationCoordinator.swift) is the single MainActor owner for queue state, the running task/stop flag, per-request batch accounting, delayed retry tasks/attempts, and capacity postponement. It exposes intentional operations (`enqueue`, `cancelQueued`, `cancelAllPending`, `confirmStopActiveTransfer`, `revokeDoneWork`, `cancelDoneRetry`/`cancelPendingRetry`, `scheduleRetry`, `noteSuccessfulTransfer`, capacity note/release) and read-only state.
- [`ArchiveBrowserViewModel`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel.swift) forwards queue/retry/accounting reads for existing views/tests with no duplicate stored state, re-emits the coordinator's publishes for SwiftUI, and injects narrow callbacks (status setter/base, root IDs, presentation refresh, shell-job publish, vault logging, drain-to-recovery). All coordinator captures of the view model are weak.
- The Done revocation bridge (`revokeBoundDoneWork` in [`ArchiveBrowserViewModel+Metadata.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+Metadata.swift)) owns only capture/dialog presentation and delegates queue/retry/stop mutations to `revokeDoneWork`.
- Queue execution stays serial with duplicate prevention by song and canonical project identity, captured root revalidation before dispatch, truthful per-request stop/cancel counts, bounded Done retries (at most 3, same token downgraded copy-only), postponed non-retryable capacity until explicit reset, and shell-job publication/lifetime cancellation preserved.

## Project Vault observation ownership

[`ArchiveVaultObservation`](../Sources/FeatureArchiveBrowser/ArchiveVaultObservation.swift) owns the prepared settings context, provider health, runtime snapshots and canonical path index, immutable card cache, archived count, and automatic-recovery task/deadline/backoff.

- Settings enter through `refreshContext(settings:songs:)`. Card reads use the prepared map without loading settings. `rebuildCards(for:)` derives the map before comparing values.
- Normal refresh uses `stageSnapshots(_:)`, projects the catalog, then refreshes cards. A changed catalog also prebuilds cards in `songs.willSet` before publishing songs. The operation-scoped phase poller uses `applyPolledSnapshots(_:songs:)`, which reuses staging and publishes a changed snapshot once; unchanged snapshots are a no-op.
- Snapshot/path validation, Keep Local pins, and generic-action blocking live beside their inputs. Archive projection may inspect filesystem paths and load metadata; it reports metadata-read failures through the supplied warning callback. It does not initiate scans or reload settings.
- `scheduleRecovery` / `cancelRecovery` own deadline deduplication, busy checks, the 30-second backoff, and cancellation on deinitialization. Runtime execution and subsequent refresh enter through callbacks with weak view-model captures.
- The view model retains runtime refresh orchestration, status composition, archived-visibility choice, and Done enqueue decisions. An unavailable runtime clears snapshots; an unreadable journal preserves the last presentation and reports a warning. Read-only peers and a weak `objectWillChange` subscription connect the owner to existing views.

## Archive metadata editing ownership

[`ArchiveMetadataEditingCoordinator`](../Sources/FeatureArchiveBrowser/ArchiveMetadataEditingCoordinator.swift) owns edit validation and persistence ordering, notes/status undo, repair-song IDs, and delayed index persistence. It holds no catalog copy. The required immutable `ArchiveMetadataEditingHost` supplies live inputs and narrow mutation callbacks together; weak view-model captures and absent-input checks prevent edits after the host disappears.

- Notes and ordinary workflow commands pass through the per-song integrity gate and authoritative metadata persistence before requesting a catalog replacement. Late corruption refuses replacement; ordinary storage failure retains the visible edit with a warning. `ArchiveCatalogCoordinator` retains the store and integrity-reporting machinery.
- Owned, injected, and weak window-bound undo managers live in the editing owner. Explicit bind/unbind methods scrub only this owner's registrations. The weak undo target routes inverses back to the driving manager; native window behavior remains in `ArchiveWorkflowUndoBridge`.
- `scheduleIndexPersist` serializes behind its predecessor, reads live songs when firing, and checks the captured root generation. Root reset cancels but retains an in-flight predecessor so its detached write cannot overwrite a newer snapshot. Deinitialization cancels pending work.
- `repairSongMetadata` reloads and merges repaired rows and updates the repair-ID projection. Status and integrity-warning callbacks remain part of the view model's footer composition.

The remaining ownership is intentional:

| Owner | Retained responsibility and boundary |
| --- | --- |
| View model: catalog/browse | `songs` / `scannedSongs`, selected shelf/filter/search state, prepared search index, catalog replacement and selection reconciliation. Owners read current inputs and return results rather than keeping a second catalog. |
| View model: roots/scan host | Roots, bookmarks, root generation and scan-result application; `ArchiveScanOrchestrator` owns scan execution. |
| View model: UI integration | Selection/navigation, playback and preview-analysis invalidation, collaborator/intelligence projections, exports and status composition. |
| View model: Vault authorization | Capture/confirmation/restore presentation, runtime dispatch, and the Done revocation bridge. Metadata commands request Done capture or revocation through callbacks; they do not create or reuse authorization. |
| `ProjectVaultOperationCoordinator` | Queue, active/busy state, cancellation, retry and capacity accounting. The observation and editing owners do not mutate its storage. |
| `ArchiveCatalogCoordinator` | Scan reconciliation, persistence and per-song metadata integrity. The editing owner controls transaction ordering above this layer. |

The metadata extension retains the user-created-folder flow and the catalog/selection applier, plus preview/playback integration. It delegates editing and undo commands through the owner API; bound Done and ordinary status commits keep their existing distinct authorization paths.

## Shell navigation and tool-page scaffold (2026-09)

- `HubNavigationHistory` (AppCore) gives the shell browser-style back/forward. It is created once in
  `AppComposition` and passed to both `ToolContext` values (the archive VM and the shell must share
  the same instance). Tools with inner pages record an opaque route and register a restorer.
- `ToolFeature.makeTitleBarAccessory(context:)` lets a tool place a control in the window title bar
  (the archive's board⇄list flip icon).
- Production tools render through `HubInspectorPage` (content column + fixed inspector rail). Layout
  rules and keylines: `docs/design-contract.md`.

## Project Vault bound authorization

- Every explicit Archive confirmation captures a `ProjectVaultArchiveAuthorization` before the dialog;
  the exact token travels confirmation → queue → bounded Done retries and is never re-captured or
  escalated at execution (copy-only stays copy-only; drift fails closed in the runtime).
- The nil-authorization overload (automatic Done, relaunch) is always copy-only; a new destructive
  action needs a fresh confirmation. Undo or leaving Done revokes that song's capture, dialog,
  queued Done operation, retry budget, and inflight Done task; revoked approvals are never reused.
- Cancel copy is truthful about the removal boundary: stopping before verification keeps Active;
  at/after removal the fate is uncertain, partial copies are never claimed verified, and review
  stays via Restore & Open / Recover Verified Project.

## Running work and quit

[ADR 019](decisions/019-running-work-and-quit.md) has the full contract.

- Every tool registers work that must not be cut off with `ShellJobStatusCenter` (runner jobs, plus extra sources
  with `blocksQuit`; recorder takes and helper installs register unlisted). `quitBlockingWork` is the one list quit
  reads.
- `applicationShouldTerminate` maps `HubTerminationCoordinator.answerTerminateRequest`: nothing running quits at once;
  otherwise the delegate's `confirmQuit` shows one alert naming the work, and on confirm every cancel runs and the
  delegate returns `.terminateLater`. The coordinator replies once the work has unwound or after 5 s.
- `applicationWillTerminate` reaps helper process groups that are still alive (`LiveProcessGroupRegistry`: SIGTERM,
  up to 1 s, then SIGKILL).

## Safety architecture

Read-only archive writes are denied via
[`ReadOnlyArchivePolicy.enforceNoWrite(at:archiveRoots:)`](../Sources/NikoMusicCore/Safety/ReadOnlyArchivePolicy.swift)
(and the single-root `enforceNoWrite(at:archiveRoot:)` overload):

```swift
try ReadOnlyArchivePolicy().enforceNoWrite(at: outputURL, archiveRoots: archiveRoots)
// throws ReadOnlyArchivePolicyError.writeDenied when outputURL resolves
// equal to or inside any protected archive root (symlinks resolved)
```

Prospective paths are gated with
[`PathSafety.resolve(_:allowedRoots:)`](../Sources/NikoMusicCore/Safety/PathSafety.swift):

```swift
let resolved = try PathSafety().resolve(userPath, allowedRoots: settings.roots)
```

[`MusicItemOpener.openLatestCPR(for:dryRun:allowedRoots:)` / `revealLatestCPR(for:dryRun:allowedRoots:)`](../Sources/NikoMusicCore/Opening/MusicItemOpener.swift):

- `dryRun == true`: writes a `[dry-run]` line to the injected log and opens nothing (E2E uses this).
- `dryRun == false`: calls the injected `WorkspaceOpening` (`open` or `revealInFinder`). Core never imports AppKit;
  the app and feature targets supply the `NSWorkspace`-backed opener.

Vault destinations are restore/review handles, never generic filesystem authority; authorization checks, path safety, and actual file operations live in the runtime/engine and are unchanged by UI refactors.

## Testing architecture

| Layer | Test home |
|-------|-----------|
| Core scanner/ranker/search | `Tests/NikoMusicCoreTests/` + fixtures under `Fixtures/CubaseArchive/` |
| Feature VM/UI logic + Vault operation owner | `Tests/FeatureArchiveBrowserTests/` (`ProjectVaultOperationCoordinatorTests`, `BoundArchiveAuthorizationTests`, `ProjectVaultQueueLivePhaseTests`, `ArchiveWorkflowUndoWiringTests`) |
| Registry integration | `Tests/AppCoreTests/FeatureRegistryTests.swift` |
| User E2E | `script/e2e_user_smoke.sh` + env vars `NIKO_MUSIC_HUB_FIXTURE_ROOT`, `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` |

- Fixture-backed Vault tests use `FriendsWorkflowFixture` (temporary Active/Archive roots, `LiveProjectVaultRuntime` with safe probes); no real music data.
- Fake-runtime timing uses deterministic entry gates plus bounded polling; no blanket timeout increases.
