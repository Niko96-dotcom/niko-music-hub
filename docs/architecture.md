# Architecture — Niko Music Hub

Last verified: 2026-09-26

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
├── AppCore                    # ToolFeature, registry, jobs, inbox, settings, Vault runtime
└── NikoMusicCore              # scan, rank, search, open safety, catalog helpers
```

- `FeatureArchiveBrowser` depends on `AppCore` and `NikoMusicCore` only.
- Feature modules stay independent except the documented Stem Separation → Downloader exception.
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

### `AppCore` (shared)

- `ToolFeature` / `ToolRegistry` / `ToolContext`, `JobRunner`, `OutputInbox`, `SettingsStore` (`UserDefaultsSettingsStore`).
- Shell jobs: `ShellJobStatusCenter`, `CancelCopy`.
- Project Vault runtime: `LiveProjectVaultRuntime`, `ProjectVaultOperating`, and admission/capacity/activity probes; it uses the transfer/catalog SQLite stores owned by `NikoMusicCore/Persistence`.
- Shared UI: `ToolHeaderBlock`, hub design tokens (see `docs/design-contract.md`).

### `FeatureArchiveBrowser` (SwiftUI feature)

- [`ArchiveBrowserFeature.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserFeature.swift): `ToolFeature` conformance (`archive-browser`).
- [`ArchiveBrowserViewModel.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel.swift): roots, browse, selection, scan host, metadata, Vault presentation/confirmations.
- Vault operation extensions: `+ProjectVaultQueue.swift`, `+ProjectVaultArchive.swift`, `+ProjectVault.swift`, `+ProjectVaultActions.swift`, `+ProjectVaultRestore.swift`, `+ProjectVaultRecovery.swift`, `+Metadata.swift` (Done revoke), `+Scan.swift` (root-bound clears).
- Coordinators: [`ArchiveScanOrchestrator`](../Sources/FeatureArchiveBrowser/ArchiveScanOrchestrator.swift), [`ArchiveCatalogCoordinator`](../Sources/FeatureArchiveBrowser/ArchiveCatalogCoordinator.swift), [`ProjectVaultOperationCoordinator`](../Sources/FeatureArchiveBrowser/ProjectVaultOperationCoordinator.swift).
- Views: `ArchiveBrowserView`, `SongDetailView`, board/list/analytics subviews (see `docs/design-contract.md`; do not regress).

## Persistence, services, composition

- Settings: `UserDefaultsSettingsStore` owns `AppSettings` (music roots, vault bindings, Keep Local pins). Vault presentation reads settings only at explicit boundaries (`refreshProjectVaultPresentationContext`).
- Archive persistence (production `AppComposition.swift:74-126`): one shared `SQLiteArchiveDatabase` backs `SQLiteArchiveIndexStore` (`ArchiveIndexStoring`), `SQLiteSongUserMetadataStore` (`SongUserMetadataStoring`), `SQLiteCollaboratorStore` (`CollaboratorStoring`), `SQLiteProjectCatalogStore`, and `SQLiteVaultTransferStore`. SQLite stores live in `NikoMusicCore/Persistence`; the Vault runtime (`LiveProjectVaultRuntime`, `ProjectVaultOperating`) lives in `AppCore`. Scans reconcile through `ArchiveCatalogCoordinator`.
- Song metadata: `SongUserMetadataStoring` SQLite rows (titles, aliases, notes, workflow status, collaborators); per-song merge/commit path with corrupt-row gating.
- Vault transfers: `SQLiteVaultTransferStore` over `SQLiteArchiveDatabase` (transfer journal is authoritative for phases/recovery).
- Vault catalog: `SQLiteProjectCatalogStore` (project records, locations, identity reviews).
- Runtime composition: `LiveProjectVaultRuntime` is built with settings/transfer/catalog stores plus storage-provider, opener, activity/capacity probes; injected into the archive view model as `ProjectVaultOperating`.
- App composition builds one `HubNavigationHistory`, one settings store suite, job center, diagnostics, and file actions, then passes the same `ToolContext` values to the shell and features.

## Project Vault operation ownership

- [`ProjectVaultOperationCoordinator`](../Sources/FeatureArchiveBrowser/ProjectVaultOperationCoordinator.swift) is the single MainActor owner for queue state, the running task/stop flag, per-request batch accounting, delayed retry tasks/attempts, and capacity postponement. It exposes intentional operations (`enqueue`, `cancelQueued`, `cancelAllPending`, `confirmStopActiveTransfer`, `revokeDoneWork`, `cancelDoneRetry`/`cancelPendingRetry`, `scheduleRetry`, `noteSuccessfulTransfer`, capacity note/release) and read-only state.
- [`ArchiveBrowserViewModel`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel.swift) forwards queue/retry/accounting reads for existing views/tests with no duplicate stored state, re-emits the coordinator's publishes for SwiftUI, and injects narrow callbacks (status setter/base, root IDs, presentation refresh, shell-job publish, vault logging, drain-to-recovery). All coordinator captures of the view model are weak.
- Metadata Undo (`revokeBoundDoneWork` in [`ArchiveBrowserViewModel+Metadata.swift`](../Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+Metadata.swift)) owns only capture/dialog presentation and delegates queue/retry/stop mutations to `revokeDoneWork`.
- Queue execution stays serial with duplicate prevention by song and canonical project identity, captured root revalidation before dispatch, truthful per-request stop/cancel counts, bounded Done retries (at most 3, same token downgraded copy-only), postponed non-retryable capacity until explicit reset, and shell-job publication/lifetime cancellation preserved.

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

- `dryRun == true`: append to diagnostics/log file; no `NSWorkspace.open`
- `dryRun == false`: `NSWorkspace.shared.open(cprURL)` or reveal-in-Finder variant for E2E

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
