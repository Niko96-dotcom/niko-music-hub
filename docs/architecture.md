# Architecture — Niko Music Hub

Last verified: 2026-09-27

New here? Start with the [architecture map](architecture-map.md): entry points, main flows, state owners,
seams, gates, and where the code differs from the principles below. This page holds the ownership detail.

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

Downloader shows a URL-derived title before provider lookup, then replaces it with the resolved media title when the download job starts.

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
  `ArchiveStorageProvider.prepareForRestoreInventory` is explicit, admitted
  preparation for linked restores: the mounted-folder adapter can coordinate
  reads of ordinary cloud placeholders before their real metadata is available.
  Metadata-only browsing/locality checks never download content. Known managed
  restores materialize only their recorded files and verify the saved manifest.
- `Persistence/`: the SQLite stores (`SQLiteArchiveDatabase` and the index, metadata, collaborator, catalog and
  Vault transfer stores).
- `Browse/` (filters, sort, smart shelves, health report), `Intelligence/` (archive intelligence, index export),
  `Preview/` (mixdown BPM/key estimation, hook locator).
- `Support/`: the helpers that keep a 10,000-song archive fast without changing results. `ParallelMap` and
  `Array.equalsConcurrently` are order-preserving parallel map and equality with a per-call thread budget (use them
  only for pure per-element work: the `ParallelMap` transform is `@Sendable` and its elements are `Sendable`, so the
  compiler checks that; Foundation's locale and JSON paths stop scaling past a handful of threads);
  `FastISO8601` parses the one timestamp spelling the app writes and leaves every other spelling to Foundation.
  `Scanning/CompiledRegex` holds fixed filename patterns compiled once. `PreviewAutoSelectionNormalizer.currentVersion`
  is recorded in the cached snapshot; a current snapshot skips the launch re-ranking except for songs with hidden
  previews (bump the version when detection, ranking or title resolution changes; `PreviewSemanticsVersionTests`
  enforces it). `Scanning/ScanWorkerBudget` decides how many
  song folders a full scan walks at once: the smaller of the root volume's limit (network 2, other external 4,
  internal 8) and the caller's budget (a scan someone waits for, including a first scan: 8; a rescan behind cached
  songs already on screen: 4). Measurements and the benchmark tools:
  `docs/performance/archive-startup-2026-10-20.md`, `script/performance/`, `script/benchmark_scan_workers.sh`
  (read-only worker sweep on a real archive disk), `script/bakeoff/` (synthetic 1k/10k archive and isolated launch).
  Memory: `SQLiteArchiveIndexStore` saves by diffing against the songs its rows hold (`SnapshotRowsMemo`, `SongRowDiff`),
  so an unchanged catalog costs no JSON and no row writes, and the launch load of a current snapshot records what the
  rows hold; `ConfidenceReasonPool` keeps one array per distinct list of preview confidence reasons; `ArchiveFileURL`
  stores scanned file URLs as fresh compact `NSURL` values (enumerator URLs carry prefetched file properties);
  `SongCatalogDeduplicator.uniqueByID` returns a catalog without repeats unchanged and `sharingUnchangedValues` reuses
  the held value of every song a rescan left equal; `[Song].songsDiffering(from:)` finds the songs a rescan changed.

### `AppCore` (shared)

`AppCore` holds two things: the shared shell kit, and (until it gets its own target) the Project Vault runtime.

- Shell kit: `ToolFeature` / `ToolRegistry` / `ToolContext`, `JobRunner`, the Output Inbox (`OutputInbox/`),
  `SettingsStore` (`UserDefaultsSettingsStore`), diagnostics, `HelperTools/` (helper locator, probe, status owner,
  installer, Set Up model; see [Helper tools](#helper-tools)), `Archive/` (FSEvents archive-root watcher), `Audio/` (WAV output spec and verification), `QuickAccess/`
  (router, menu bar model), `Navigation/` (`HubNavigationHistory`).
- Shell jobs and quit: `ShellJobStatusCenter`, `CancelCopy`, `HubTerminationCoordinator` (see
  [Running work and quit](#running-work-and-quit)); Esc and ⌘. routing (`InAppJobCancelRouting`, see
  [Tool self-description](#tool-self-description)).
- Project Vault runtime: `LiveProjectVaultRuntime`, `ProjectVaultOperating`, the admissions and the capacity probe (`FoundationProjectVaultCapacityProbe`); it uses the transfer/catalog SQLite stores owned by `NikoMusicCore/Persistence`. The activity probe (`SystemVaultAutomationActivityProbe`) lives in `NikoMusicCore/Vault/VaultAutomation.swift`.
- Shared UI: `ToolHeaderBlock`, `HubInspectorPage`, hub design tokens (see `docs/design-contract.md`).
- `HubRelativeTime` formats relative dates in English, matching the app's UI independently of the system locale.
- Recorder startup explains the macOS system-audio prompt. Stop during startup waits for the capture backend to settle, shows why it is waiting, and reports when no recording began instead of silently returning to idle.

### `FeatureArchiveBrowser` (SwiftUI feature)

- [`ArchiveBrowserFeature.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserFeature.swift): `ToolFeature` conformance (`archive-browser`).
- [`ArchiveBrowserViewModel.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel.swift): loaded roots (it follows the stored scan list, see [Archive scan list](#archive-scan-list)), browse, selection, scan host, and integration with metadata/Vault owners.
- Vault operation extensions: `+ProjectVaultQueue.swift`, `+ProjectVaultArchive.swift`, `+ProjectVault.swift`, `+ProjectVaultActions.swift`, `+ProjectVaultRestore.swift`, `+ProjectVaultRecovery.swift`, `+Metadata.swift` (Done revoke), `+Scan.swift` (root-bound clears).
- Coordinators: [`ArchiveScanOrchestrator`](../Sources/FeatureArchiveBrowser/ArchiveScanOrchestrator.swift), [`ArchiveCatalogCoordinator`](../Sources/FeatureArchiveBrowser/ArchiveCatalogCoordinator.swift), [`ProjectVaultOperationCoordinator`](../Sources/FeatureArchiveBrowser/ProjectVaultOperationCoordinator.swift), [`ArchiveMetadataEditingCoordinator`](../Sources/FeatureArchiveBrowser/ArchiveMetadataEditingCoordinator.swift) (song-metadata mutation ordering), [`ArchiveVaultObservation`](../Sources/FeatureArchiveBrowser/ArchiveVaultObservation.swift) (Vault observation/presentation).
- Playback: [`ArchivePreviewSession`](../Sources/FeatureArchiveBrowser/ArchivePreviewSession.swift), held by the view model (see [Archive preview playback](#archive-preview-playback)).
- Views: `ArchiveBrowserView`, `SongDetailView`, board/list/analytics subviews (see `docs/design-contract.md`; do not regress).
- A board lane is an `NSTableView` (`ArchiveBoardNativeSongList`) with reusable rows; each row hosts the unchanged
  SwiftUI `ArchiveBoardSongCard`. AppKit owns the document height, so a fling to the end always realizes the last card.
  Measurements and known costs: `docs/performance/archive-board-2026-10-21.md`.
- Horizontal board movement uses `ArchiveBoardHorizontalScroll`: one native viewport whose document directly
  contains the retained column drop hosts. It adds no SwiftUI hosting graph. Lane rectangles are read only during
  drag edge scrolling; offsets are never published as SwiftUI state. Presentation equality reuses the catalog's
  shared-storage comparisons. Hover suppression tracks only the controls under the pointer. Scroll activity observes
  only the viewport and native lanes' own scroll/clip views; subscriptions end on detach or destruction and refresh
  when a lane is reused with a different board controller. Hover uses a 0.10-second ease-out (disabled by Reduce
  Motion); lane/row motion remains 0.16 seconds. Live scroll end restores hover synchronously; one board-local
  pointer tracking area clears unphased-wheel suppression on the first move, without waiting for the idle timer.
  See `docs/performance/archive-horizontal-scroll-2026-10-21.md` for the measured comparison and limitations.
- The board stays mounted under the song detail page (`ArchiveBrowserViewModel.showsBoardPage`): going back must not
  rebuild its lanes. While covered it is transparent, takes no hits, is hidden from accessibility, and its native lane
  hosts are hidden; lanes rewind to the top when the detail page opens. Leaving for the list or analytics drops it.
- Applying a rescan (`applyCatalogScanUpdate`) reacts to the changed songs only, keeps the held catalog arrays when
  nothing changed, skips the browse projection for an unchanged catalog and releases the scan result off the main
  thread (`OffMainRelease`).

## Persistence, services, composition

- Settings: `UserDefaultsSettingsStore` owns `AppSettings` (music roots, vault bindings, Keep Local pins). Vault presentation reads settings only at explicit boundaries (`refreshProjectVaultPresentationContext`). The archive's scan list is edited only through `ArchiveScanList` ([Archive scan list](#archive-scan-list)).
- Archive persistence (production `AppComposition.make()`): one shared `SQLiteArchiveDatabase` backs `SQLiteArchiveIndexStore` (`ArchiveIndexStoring`), `SQLiteSongUserMetadataStore` (`SongUserMetadataStoring`), `SQLiteCollaboratorStore` (`CollaboratorStoring`), `SQLiteProjectCatalogStore`, and `SQLiteVaultTransferStore`. SQLite stores live in `NikoMusicCore/Persistence`; the Vault runtime (`LiveProjectVaultRuntime`, `ProjectVaultOperating`) lives in `AppCore`. Scans reconcile with stored user metadata through `ArchiveCatalogCoordinator`. Project identity in `SQLiteProjectCatalogStore` is reconciled only by the Vault runtime, when a song is archived (`LiveProjectVaultRuntime+Catalog.swift`).
- Song metadata: `SongUserMetadataStoring` SQLite rows (titles, aliases, notes, workflow status, collaborators); per-song merge/commit path with corrupt-row gating.
- Vault transfers: `SQLiteVaultTransferStore` over `SQLiteArchiveDatabase` (transfer journal is authoritative for phases/recovery).
- Vault catalog: `SQLiteProjectCatalogStore` (project records, locations, identity reviews).
- Runtime composition: `LiveProjectVaultRuntime` is built with the settings, transfer and catalog stores and a project opener; storage providers and activity/capacity probes use their production defaults. It is injected into the archive view model as `ProjectVaultOperating`.
- App composition builds one `HubNavigationHistory`, one settings store suite, job center, diagnostics, and file actions, and one `ToolContext` over them, before the archive view model (whose feature value the registry needs). Launch warnings (a store that failed to open, a failed registry) go to `AppShellView` as `persistenceIssues`, their only reader.

## Project Vault operation ownership

- [`ProjectVaultOperationCoordinator`](../Sources/FeatureArchiveBrowser/ProjectVaultOperationCoordinator.swift) is the single MainActor owner for queue state, the running task/stop flag, per-request batch accounting, delayed retry tasks/attempts, and capacity postponement. It exposes intentional operations (`enqueue`, `cancelQueued`, `cancelAllPending`, `confirmStopActiveTransfer`, `revokeDoneWork`, `cancelDoneRetry`/`cancelPendingRetry`, `scheduleRetry`, `noteSuccessfulTransfer`, capacity note/release) and read-only state.
- [`ArchiveBrowserViewModel`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel.swift) forwards queue/retry/accounting reads for existing views/tests with no duplicate stored state, re-emits the coordinator's publishes for SwiftUI, and injects narrow callbacks (status setter/base, root IDs, presentation refresh, shell-job publish, vault logging, drain-to-recovery). All coordinator captures of the view model are weak.
- The Done revocation bridge (`revokeBoundDoneWork` in [`ArchiveBrowserViewModel+Metadata.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+Metadata.swift)) owns only capture/dialog presentation and delegates queue/retry/stop mutations to `revokeDoneWork`.
- Successful Undo from Done refreshes the footer even when archiving was paused and no queued request exists. Refused metadata commits retain their warning and do not report success.
- Queue execution stays serial with duplicate prevention by song and canonical project identity, captured root revalidation before dispatch, truthful per-request stop/cancel counts, bounded Done retries (at most 3, same token downgraded copy-only), postponed non-retryable capacity until explicit reset, and shell-job publication/lifetime cancellation preserved.

## Project Vault observation ownership

[`ArchiveVaultObservation`](../Sources/FeatureArchiveBrowser/ArchiveVaultObservation.swift) owns the prepared settings context, provider health, runtime snapshots and canonical path index, immutable card cache, archived count, and automatic-recovery task/deadline/backoff.

- Settings enter through `refreshContext(settings:songs:)`. Card reads use the prepared map without loading settings. `rebuildCards(for:)` derives the map before comparing values.
- Normal refresh uses `stageSnapshots(_:)`, projects the catalog, then refreshes cards. A changed catalog also prebuilds cards in `applyCatalogEdit(_:)` before publishing songs. The operation-scoped phase poller uses `applyPolledSnapshots(_:songs:)`, which reuses staging and publishes a changed snapshot once; unchanged snapshots are a no-op.
- Snapshot/path validation, Keep Local pins, and generic-action blocking live beside their inputs. Archive projection may inspect filesystem paths and load metadata; it reports metadata-read failures through the supplied warning callback. It does not initiate scans or reload settings.
- `scheduleRecovery` / `cancelRecovery` own deadline deduplication, busy checks, the 30-second backoff, and cancellation on deinitialization. Runtime execution and subsequent refresh enter through callbacks with weak view-model captures.
- The view model retains runtime refresh orchestration, status composition, archived-visibility choice, and Done enqueue decisions. An unavailable runtime clears snapshots; an unreadable journal preserves the last presentation and reports a warning. Read-only peers and a weak `objectWillChange` subscription connect the owner to existing views.

## Archive metadata editing ownership

Loose CPR/ALS versions at an archive root use a stable song ID derived from that root and
the scanner's normalized project-name group. `folderPath` remains the latest physical file
for opening; it is not the metadata key. Old snapshot payloads derive the same stable ID
when decoded. Before merging metadata at launch or after a scan, the SQLite metadata store
migrates legacy version-path keys, status history and repair-backup ownership in one
transaction. Values, timestamps and raw corrupt rows are preserved. Multiple metadata rows
claiming one group refuse the entire migration and block edits through the existing load
failure gate; no conflicting record is overwritten. Ordinary loads remain read-only, and
scans never upsert metadata values. Snapshot rows whose stored keys predate this identity
must be rewritten before the unchanged-row memo is enabled.

[`ArchiveMetadataEditingCoordinator`](../Sources/FeatureArchiveBrowser/ArchiveMetadataEditingCoordinator.swift) owns edit validation and persistence ordering, notes/status undo, repair-song IDs, and delayed index persistence. It holds no catalog copy. The required immutable `ArchiveMetadataEditingHost` supplies live inputs and narrow mutation callbacks together; weak view-model captures and absent-input checks prevent edits after the host disappears.

- Notes and ordinary workflow commands pass through the per-song integrity gate and authoritative metadata persistence before requesting a catalog replacement. Late corruption refuses replacement; ordinary storage failure retains the visible edit with a warning. `ArchiveCatalogCoordinator` retains the store and integrity-reporting machinery.
- Every notes commit (title, aliases, note, the three-field save, the draft flush) and every ordinary status commit registers its own Undo in the editing owner: only when it was not refused and a value changed, with the values the catalog held before. Views only keep their drafts and read the outcome.
- Owned, injected, and weak window-bound undo managers live in the editing owner. Explicit bind/unbind methods scrub only this owner's registrations. The weak undo target routes inverses back to the driving manager; native window behavior remains in `ArchiveWorkflowUndoBridge`.
- `scheduleIndexPersist` serializes behind its predecessor, reads live songs when firing, and checks the captured root generation. Root reset cancels but retains an in-flight predecessor so its detached write cannot overwrite a newer snapshot. Deinitialization cancels pending work.
- `repairSongMetadata` reloads and merges repaired rows and updates the repair-ID projection. Its status and warning callbacks write the archive footer through the view model; after a repair, `refreshSongDetailsWarning` replaces only a song-details warning (see [Archive footer ownership](#archive-footer-ownership)).

The remaining ownership is intentional:

| Owner | Retained responsibility and boundary |
| --- | --- |
| View model: catalog/browse | The song catalog through `applyCatalogEdit(_:)` (see [Archive song catalog](#archive-song-catalog)), selected shelf/filter/search state, prepared search index and selection reconciliation. Owners read current inputs and return results rather than keeping a second catalog. |
| View model: roots/scan host | Roots, bookmarks, root generation and scan-result application; `ArchiveScanOrchestrator` owns scan execution. |
| View model: UI integration | Selection/navigation (see [Archive page state](#archive-page-state)), playback and preview-analysis invalidation, collaborator/intelligence projections, exports, and the footer methods (the footer rules belong to `ArchiveFooterStatus`). |
| View model: Vault authorization | Capture/confirmation/restore presentation, runtime dispatch, and the Done revocation bridge. Metadata commands request Done capture or revocation through callbacks; they do not create or reuse authorization. |
| `ProjectVaultOperationCoordinator` | Queue, active/busy state, cancellation, retry and capacity accounting. The observation and editing owners do not mutate its storage. |
| `ArchiveCatalogCoordinator` | Scan reconciliation, persistence and per-song metadata integrity. The editing owner controls transaction ordering above this layer. |

The metadata extension retains the user-created-folder flow, plus preview/playback integration; edited songs reach the catalog through `applyCatalogEdit(.replace(_:))`. It delegates editing and undo commands through the owner API; bound Done and ordinary status commits keep their existing distinct authorization paths.

## Archive page state

The Archive Browser's page (`viewMode`: board, board detail, list, analytics; `listShowsDetail` for the compact list's
detail) belongs to `ArchiveBrowserViewModel`. Views state intent and never write it: `openSongDetail(_:)`,
`showBoard()` (back from the detail or analytics, keeping the selection), `setBrowseLayout(list:)`, `showAnalytics()`,
`clearSelection(stopPlayback:)` and `restoreNavigationRoute(_:)`. `ArchiveViewIntentSourceTests` fails on a write
outside `ArchiveBrowserViewModel*.swift`. When the page changes, `ArchiveBrowserView` gives the archive the keyboard
(unless the search field has it), so Esc and the song shortcuts work after a page change that did not come from a
click: VoiceOver's "Open song detail", the Song menu, Back/Forward (`ArchiveKeyboardFocusTests`).

Gates follow the same rule: a view asks the view model the question the edit coordinator also asks. The song detail's
status menu uses `canMutateWorkflowStatus(for:)`, like board drops and the Song menu; the shorter
`blocksGenericProjectVaultFileActions(for:)` stays the gate for metadata edits and file actions. (Board and list cards
still use only the card-state policy; see the map's open questions.)

## Archive song catalog

[`SongCatalog`](../Sources/FeatureArchiveBrowser/SongCatalog.swift) holds the songs the Archive Browser knows: the
scan baseline (`scannedSongs`, which the index persist writes), the visible list (`songs`: the baseline plus
archive-only Vault projections when "Show archived" is on) and an id index. It is a value with no I/O. Every edit
reports a `SongCatalogChange`: the changed songs with their old values and the removed songs.

- `ArchiveBrowserViewModel.applyCatalogEdit(_:)` is its only writer. The setter of `songCatalog` is private to
  `ArchiveBrowserViewModel.swift`, and `songs` and `scannedSongs` are read-only, so another writer does not compile.
- Six edits: `load` (the cached index; tests seed the catalog through it), `rescan`, `reproject` (Vault snapshots,
  "Show archived", Vault settings, roots), `add` (New Song), `replace` (metadata edits and collaborator removal, one
  batch) and `clear` (a root change). All but `replace` and `clear` run the Vault projection.
- The follow-up work of a change lives in that function. A new visible list rebuilds the Vault card cache before it
  publishes. Every change recomputes the browse results (they reconcile the selection), refreshes intelligence and
  open analytics, and updates the per-song caches (`updatePerSongCaches(for:)`: changed and removed songs only, never
  new ones). `load`, `rescan` and `add` sync the repair state; `rescan` and `add` persist the index, and `reproject`
  does when it changed the baseline. Edits leave the index persist to `ArchiveMetadataEditingCoordinator`.
- Equal lists stay as held: an unchanged 10,000-song rescan keeps one copy of the catalog and reports an empty
  change. The scan shares unchanged song values with the held baseline before it projects.
- An owner object like `ArchiveVaultObservation` was considered and not chosen: the follow-ups are view-model state,
  so each edit would cross two objects and a callback, and the card cache must still be built before the publish.
  Revisit that only if the projection gets a second user.

## Archive preview playback

[`ArchivePreviewSession`](../Sources/FeatureArchiveBrowser/ArchivePreviewSession.swift) owns the archive's playback:
the loaded song and preview, the paused-transport rule (a pause re-arms the selected song), the recording pause and
the headphone-unplug pause. Its `ArchivePreviewPlayer` is the only AVFoundation player in the archive, so one preview
plays at a time by construction; no coordinator sits between players.

- `ArchiveBrowserViewModel.previewSession` holds it. The view model creates it with its other owners; production
  builds one view model, so the app has one session for its lifetime. Every write of `selectedSong` reaches it
  (`synchronizePreviewSelection()`, also for restored routes and catalog reconciliation), and the lifecycle resets (a
  root change; the loaded song hidden or gone from the catalog) call `clear()`.
- Views get it by initializer, never by a global: `ArchiveBrowserView` and `SongDetailView` from the view model,
  `SongCardView`, `ArchiveBoardCardView` and `ArchivePreviewRowView` as a parameter, and the shell builds
  `ArchivePersistentPlayerView(viewModel:onOpenSong:)` from the view model it already holds.
- `ArchivePreviewSessionTests` checks the wiring through the view model: a selection write and a restored route arm
  its session, the bar's Open action returns to that view model, and two view models never share a session. The
  transport rules themselves are in
  [design-contract.md § Archive selection and persistent preview player](design-contract.md#archive-selection-and-persistent-preview-player).
- The recording signal is still the process-wide `AudioCaptureActivity.shared`, shared with the recorder (map gap 5).

## Archive scan list

The folders the Archive Browser scans live only in the stored settings (`AppSettings.musicRoots`).
[`ArchiveScanList`](../Sources/AppCore/Settings/ArchiveScanList.swift) (AppCore) owns their rules; it edits settings
values and never a file.

- `scannedRoots(in:)`: which stored roots the archive scans (enabled Scan-only roots, plus the Vault Active root while
  Vault is on; never the Vault Archive root). Settings > Music archive lists the same roots, so a root whose access
  failed is listed and can be removed; the Vault Active root shows without Remove.
- `adding(_:bookmark:to:)` and `removing(_:from:)`: the two edits a person makes. An edit changes only the matching
  record, matched by canonical path or by where its bookmark points, so Vault roots, disabled records and roots whose
  access failed keep their records. Adding the folder of the Vault Active root repairs that root in place; a different
  folder never rebinds a Vault root. Vault roots change in the Project Vault pane (`VaultRootManager`).
- Writers: Settings > Music archive (through `HubSettingsSession.persistSettings`, so a failure shows in Settings'
  banner), and the board's Add Folder and Grant Access and Set Up's Choose Folder (through
  `ArchiveBrowserViewModel.addRoots`, failures in the archive footer). A failed save changes nothing.
- The archive follows the store. It subscribes to `ToolContext.appSettings` and answers every save, whoever made it,
  with `followStoredSettings()`. The reaction reads the store, so a late publish cannot roll it back, and compares
  with what it last loaded (`ArchiveFollowedSettings`). A Keep Local pin or another Vault choice only refreshes the
  cards. Changed roots load again: added folders keep the catalog and scan; a removal or a new Vault binding resets
  the root-bound state, keeps an unrelated footer warning and scans what is left; a Vault binding change also runs
  Vault recovery. The archive's own add runs the reaction at once, and the later publish finds nothing new. A
  settings repair calls it too, after clearing the settings warning.
- The archive keeps the read side: resolving bookmarks, holding security-scoped access, the access failure,
  `writeProtectedRoots()`.
- Limits: fixture runs (`NIKO_MUSIC_HUB_FIXTURE_ROOT`) pin the loaded roots to the fixture, so an edit is saved but
  the board keeps the fixture. A writer in another process (the CLI) is not followed.

## Helper tools

The outside programs the tools run (yt-dlp, FFmpeg, ffprobe, demucs-mlx) are found, checked and reported by
`AppCore/HelperTools/`:

- `HelperToolLocator` finds a helper: the saved path, then the Tools folder, then system folders. One instance is
  built by `AppComposition` from `MusicHubRuntimeEnvironment`, which reads `NIKO_MUSIC_HUB_TOOLS_DIR` and
  `NIKO_MUSIC_HUB_IGNORE_SYSTEM_HELPERS`; the locator reads no process environment.
- `HelperToolProbe` runs a helper's version check (yt-dlp `--version` with the staleness rule, FFmpeg `-version`,
  demucs-mlx `--list-models`) and returns one `HelperToolStatus`: ready, missing, outdated (yt-dlp only) or broken.
  Run-time gates (a download, the Converter's FFmpeg fallback) call it at start.
- `HelperToolHealth`, one per app in `ToolContext.helperHealth`, holds the last status per helper. It probes a helper
  when a surface first asks (`check`), again when its saved path changes (it follows `appSettings`) and when the Set Up
  model finishes an install, never at launch. `recheck` probes now (Try Again, the sidebar strip opening).
- The Downloader shows `DownloadState.ytDlpUnavailable(status)` with one card per status and checks a failed URL again
  once yt-dlp is ready; Stem Separation and the sidebar strip show the owner's statuses. No feature module builds a
  probe or a locator (`HelperToolHealthTests` source test).
- Set Up's Installed / Not Installed rows stay a file check (`HelperToolSetupModel`): a bundle can be installed while
  one of its helpers is broken.

## Archive footer ownership

[`ArchiveFooterStatus`](../Sources/FeatureArchiveBrowser/ArchiveFooterStatus.swift) is the one owner of what the
Archive Browser footer shows: at most one message and one warning, joined by one space.

- A message comes from a source. An **action** message (something the person did) always replaces the message and
  releases a Project Vault hold. A **Project Vault** message holds the footer until the next action message. A
  **background** message (scan progress and results) never replaces a held Vault message.
- A new warning replaces the old one. Each warning has a kind, so code that resolves a condition clears only its
  own warning: `settings` (settings repair), `rootAccess` (root recovery or removal), `projectVaultRead` (a
  successful snapshot read), `songDetails` (a repair replaces it), and `other` (cleared only by another warning or
  a root change). The kinds that clear themselves write their sentence in a factory next to the kind; a plain
  string warning is a `songDetails` warning when `SongMetadataIntegrityCopy` wrote it.
- `ArchiveBrowserViewModel.footer` is `private(set)`. The footer methods at the end of `ArchiveBrowserViewModel.swift`
  are its only writers and publish only when the footer changes. `statusMessage`, `statusBaseMessage` and
  `persistenceWarningMessage` are read-only views of it. The upload-wait Vault message is withdrawn only while it
  is still on show.
- Per-source message slots and several warnings at once were considered and not chosen: they need clearing rules
  nobody has asked for, and several warnings would not fit the footer's fixed slot. Revisit that only when a real
  report shows one warning hiding another.

## Shell navigation and tool-page scaffold (2026-09)

- `HubNavigationHistory` (AppCore) gives the shell browser-style back/forward. It is created once in
  `AppComposition` and passed to both `ToolContext` values (the archive VM and the shell must share
  the same instance). Tools with inner pages record an opaque route and register a restorer.
- `ToolFeature.makeTitleBarAccessory(context:)` lets a tool place a control in the window title bar
  (the archive's board⇄list flip icon).
- Production tools render through `HubInspectorPage` (content column + fixed inspector rail). Layout
  rules and keylines: `docs/design-contract.md`.

## Tool self-description

Shared shell code knows a tool only through what the tool says about itself. It does not branch on tool IDs to
order, route or label anything (2026-10-24, finding #9 of the 2026-10-22 review).

- **IDs.** The six product tools' IDs are defined once, in
  [`BuiltInToolIDs.swift`](../Sources/AppCore/Features/BuiltInToolIDs.swift) (`ToolFeatureID.archiveBrowser` …
  `.stemSeparation`); Settings and the Dev Tool spell theirs in their feature files. An ID is stored (the shell's
  selection, inbox items) and typed (`-ui-tool`), so it never changes. AppCore names a tool only for the curated menu
  bar list (`QuickAccessEntry.allowlist`), the router's two cross-tool requests (Search Archive…, a converter
  hand-off) and `OutputHandoff`'s Downloader file types. `ToolIDSourceTests` keeps the literals in their owners.
- **Order.** `ToolMetadata.section` (`library`, `production`, `settings`) places a tool. `ToolSection.sidebarOrder`
  is the one order: the sidebar, the Tools menu, ⌘1…⌘9, the arrow keys and the Dock menu use it. Registration order
  alone is not enough, because the Dev Tool registers after Settings. A `settings` tool opens the Settings window:
  it is never the main pane or the launch tool and has no ⌘ digit. The menu bar menu keeps its own curated order.
- **Esc and ⌘.** Each job says what the keys cancel it as (`ShellJobStatus.cancelTarget`) and whose it is
  (`sourceToolID`; `nil` for shell work such as a Vault transfer or a scan). Each tool says whether its pane keeps
  Esc (`ToolMetadata.handlesEscape`: the Archive Browser, Downloader, Stem Separation and WAV Converter).
  `InAppJobCancelRouting` is two functions over the job list: Esc on a pane that keeps Esc cancels that tool's own
  jobs (the archive owns none, so Esc stays with its views); on any other pane it cancels the shell work of the first
  target. ⌘. cancels every job of the first target present. The ⌘. order is `InAppJobCancelTarget`'s case order
  (downloads, stem separations, the conversion, the Vault transfer, the scan). A job without a target (the Dev Tool's
  sample job) is cancelled only from the jobs strip.
- **Jobs strip.** A row's verb and Cancel help come from its tool: a `JobRunner` job carries the verb and target its
  tool passed to `enqueue`; an extra source builds its own `ShellJobStatus` (the converter's in
  `ConverterJobReporting`, the Vault's and the scan's in `ShellJobStatusCopy`).

## Tool page keys

Return and Esc on a tool page have one owner each (2026-10-24, finding #10 of the 2026-10-22 review; rule in
[design-contract.md §4](design-contract.md#4-tool-pages--hubinspectorpage)).

- `HubInspectorPage` binds the page's `primaryKey` (Return) and `cancelKey` (Esc) as hidden keyboard-shortcut buttons,
  only while the key is enabled and the page is the visible one (`hubToolIsActive`). The shell keeps pages you left
  mounted, so before this a hidden page could keep Return, Esc and Space.
- Esc: the visible page's enabled cancel key, otherwise the shell's Edit ▸ Cancel ([Tool
  self-description](#tool-self-description)). AppKit gives a window's key buttons the key before the menu. The WAV
  Converter's cancel key is its soft stop; Edit ▸ Cancel chosen from the menu, ⌘. and the jobs strip stop the file
  in flight now. The stop request is not published to the view, so the key (and the visible button) stays enabled
  until the file ends, and a second Esc only repeats the request. The Downloader and Stem Separation declare no
  cancel key: the shell's Esc cancels their jobs. The Audio Recorder's cancel key stops the take.
- The BPM Tapper's tap pad and the recorder's record button answer their keys only while their page is visible; the
  tap pad gives up keyboard focus when its page is hidden and takes it back when it is shown.
- A running job's progress is `HubJobProgressRow` (bar, optional percent and elapsed line, status line); it owns the
  elapsed format.

## Project Vault bound authorization

- Every explicit Archive confirmation captures a `ProjectVaultArchiveAuthorization` before the dialog;
  the exact token travels confirmation → queue → bounded Done retries and is never re-captured or
  escalated at execution (copy-only stays copy-only; drift fails closed in the runtime).
- The automatic Done copy is the only automatic archiving: no timer, inactivity or low-space trigger
  exists (the "Archive automatically" switch was removed on 2026-10-24). `VaultAutomationScheduler`
  runs a Done archive and removes the Active copy only when its caller says so (`removesActiveCopy`,
  true only for a bound removal authorization).
- The nil-authorization overload (automatic Done, relaunch) is always copy-only; a new destructive
  action needs a fresh confirmation. Undo or leaving Done revokes that song's capture, dialog,
  queued Done operation, retry budget, and inflight Done task; revoked approvals are never reused.
- Cancel copy is truthful about the removal boundary: stopping before verification keeps Active;
  at/after removal the fate is uncertain, partial copies are never claimed verified, and review
  stays via Restore & Open / Recover Verified Project.

## Keep Local pins

[`KeepLocalPins`](../Sources/AppCore/Settings/KeepLocalPins.swift) is the one owner of Keep Local: whether a project is
pinned, which keys a pin writes and which keys unpin removes. [ADR 021](decisions/021-keep-local-pin-format.md) has the
decision.

- Storage is unchanged: `VaultSettings.keepLocalProjectIDs`, a set of strings that mixes catalog project IDs, song IDs and
  folder paths in several spellings. Older builds and recovery bundles read it, so a pin still writes every spelling
  they compare (raw, standardized, resolved, canonical). The set is `internal` to AppCore; everything else uses
  `VaultSettings.keepLocalPins` (`KeepLocalPinsSourceTests`).
- A caller describes a project with what it knows (`KeepLocalPins.Project`: project IDs, song IDs, folders). IDs match
  exactly; folders match by one canonical folder path (`KeepLocalPins.canonicalFolderPath`, which
  `ArchiveVaultObservation.vaultCanonicalPath` forwards to), so a pin under another spelling of the same folder
  counts everywhere. Matching is never weaker than the ten hand-built key sets it replaced.
- The runtime gates (capture, Done eligibility, removal admission, the runtime pin flag) and the restore pins pass the
  facts each had before; the archive browser builds one project per song (`ArchiveVaultObservation.keepLocalProject(for:)`)
  for its card flag, the automatic Done skip, and the Keep Local toggle and "Keep on this Mac" writes.
- `KeepLocalPins` values are built once per presentation-context refresh or snapshot read. An ID-only check, or a set
  without path keys, does no filesystem work, so the card for a song without a snapshot stays cheap.
- The Review Keep Local sheet's "N projects are currently pinned" counts stored keys, not projects; old keys cannot be
  grouped per project (ADR 021, Open).

## Vault folders

[`VaultFolders`](../Sources/NikoMusicCore/Vault/VaultFolders.swift) (NikoMusicCore) is the one owner of the folders the
app keeps inside the two Project Vault roots. They are an on-disk format: Vaults made by earlier versions must stay
readable, so the names, the nesting and the lowercased UUIDs never change (`VaultFoldersTests` pins the exact paths).

| Root | Folder | Holds |
| --- | --- | --- |
| Archive | `generations/<project>/generation-<transfer>` | verified copies |
| Archive | `.niko-staging/<project>/<transfer>` | an archive in progress |
| Active | `.niko-staging/<project>/<restore>` | a restore in progress |
| Active | `.niko-recovery/<transfer>/<attempt>/<folder>` | Active copies that recovery set aside |

- Reserved names, one rule per root: in the Archive root, `generations` and `.niko-staging` (any case) are never an
  ordinary archive folder; in the Active root, a path through any `.niko-` folder is never a restore destination. The
  restore sheet, the restore engine and the runtime's pinned destination apply the same Active rule
  (`isInReservedActiveFolder` resolves symlinks first).
- `VaultFolders` says where the folders are and which names are reserved. The staging, generation and destination
  checks stay with their callers (the engines, the runtime, the presentation), each with its own containment and
  symlink rules.
- `VaultFoldersSourceTests` fails when another source file spells a folder name. `VaultArchiveLayout` is a different
  concern: how file names are stored inside one generation.
- The runtime builds engines only through `LiveProjectVaultRuntime.makeTransferEngine` and `makeRestoreEngine`, so every
  engine gets the runtime's stores, clock and (for transfers) recovery policy. A transfer engine built without
  admissions refuses writes and removals.

## Tool output destination

A tool run writes only into a [`ToolOutputDestination`](../Sources/AppCore/Settings/ToolOutputDestination.swift): the
output folder and the `ToolOutputGuard` that admits it, read from one settings snapshot. `load(from:)` reads settings
with `try`; unreadable settings refuse the run and each tool shows its own sentence. A destination stays bound to its
snapshot, so a settings change during a run cannot move the rest of the run.

- Audio Recorder and Downloader load the destination in the view model when a run starts. The WAV Converter builds it
  from the snapshot its run already holds (`BatchAudioConversionUseCase`). Stem Separation loads it in the view model
  and passes it in `StemSeparationRequest` / `YouTubeStemSeparationRequest`; the service and the YouTube workflow
  admit the run folder and the download folder with it.
- Only three files build a `ToolOutputGuard` themselves: `ToolOutputDestination`, the Settings output picker (it checks
  a candidate folder before saving it) and the recovery bundle export (a folder the person chose).
  `OutputGuardSourceTests` lists them with their reasons and fails on any other.
- The Output Inbox handoff stays in each tool on purpose. Stem Separation adds a set of stems as one unit and fails the
  job when that write fails; the Downloader adds each verified file on its own; the converter and the recorder add one
  file each and warn on a failed write. A shared delivery module would hold only item construction and a `do/catch`,
  and making the failure policy the same is a product decision. Revisit it only after that decision.

## Tool recent outputs

A tool page lists its own outputs through [`ToolRecentOutputs`](../Sources/AppCore/OutputInbox/ToolRecentOutputs.swift).
The tool's view model creates it with the store, its tool ID and a limit (Audio Recorder 5, Stem Separation none) and
calls `refresh()` on appear and after its own handoff. The view observes it directly, so a list change does not pass
through the view model.

- It follows `.outputInboxDidChange` and reads `listItems()` off the main actor; filter, sort (newest first) and limit
  run there too. `items` changes only when the tool's slice changed, so another tool's output does not re-render the
  page. Requests during a pass coalesce into one follow-up pass, as in `OutputInboxRefreshModel`.
- It is read side only. It never writes the inbox, refreshes availability or takes the one-time corruption warning;
  the Output Inbox panel (`OutputInboxRefreshModel`) owns those. A failed read keeps the last list, and the panel
  shows read errors.
- `HandoffSurfacingSourceTests` fails when a feature module calls `listItems()` or observes `.outputInboxDidChange`.
- There is no inbox snapshot shared by the panel and the tool pages. Each tool would still need its own deduplicated
  slice, and the snapshot's availability refresh would write the inbox while the panel is hidden. Revisit it only if
  profiling shows the extra reads matter.

## Running work and quit

[ADR 019](decisions/019-running-work-and-quit.md) has the full contract.

- Every tool registers work that must not be cut off with `ShellJobStatusCenter` (runner jobs, plus extra sources
  with `blocksQuit`; recorder takes, helper installs and a download's title lookup register unlisted).
  `quitBlockingWork` is the one list quit reads.
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

Tool output folders (converter, downloader, recorder, stems, and the Settings output picker)
are admitted through [`ToolOutputGuard(settings:)`](../Sources/AppCore/Settings/ToolOutputGuard.swift)
(a tool run gets it from its [`ToolOutputDestination`](#tool-output-destination)),
which protects every configured music root, whatever its role or the Vault switch. It is
deliberately not the browse list (`archiveRoots`), which hides Vault roots while Vault is off;
retained archive generations stay write-protected. The archive browser's exports and New Song
use `writeProtectedRoots()`. `OutputGuardSourceTests` enforces both owners.

Settings that gate a write or a Project Vault decision are loaded with `try`, and the action is
refused when they cannot be read (`ToolOutputDestination.load(from:)`,
`ArchiveBrowserViewModel.loadSettingsForWrite()`); display-only code reads
`ToolContext.appSettings`. The few `try? …loadSettings()` reads that stay are listed with their
reasons in `OutputGuardSourceTests`.

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
