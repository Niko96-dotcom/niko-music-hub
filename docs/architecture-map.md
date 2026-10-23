# Architecture map — Niko Music Hub

Last verified: 2026-10-22 at `3ace650` (source read; `./script/ci.sh` green, see [Check baseline](#check-baseline-2026-10-22))

Start here. This page names the entry points, modules, main flows, state owners, seams and gates, and
links to the documents that hold the detail. It does not repeat them.

Each section says what kind of statement it makes:

- **Observed**: read in the source at the commit above.
- **Intended**: a documented rule; the enforcer is named where one exists.
- **Open**: not decided, or not verified.

Detail lives in [architecture.md](architecture.md) (owners, safety, Project Vault),
[design-contract.md](design-contract.md) (UI), [decisions/](decisions/) (ADRs 017–021),
[vault-durability.md](vault-durability.md) and [vault-recovery.md](vault-recovery.md).
[product-scope.md](product-scope.md) is the historical v0.1 scope.

## Entry points (observed)

| Entry point | Where | What it does |
| --- | --- | --- |
| App `@main` | `NikoMusicHubMain.main` in [NikoMusicHubApp.swift](../Sources/NikoMusicHub/NikoMusicHubApp.swift) | Resolves an isolated settings suite (`IsolatedAppLaunch`, exit 78 on a refused suite), then starts `NikoMusicHubApp` |
| Composition root | `AppComposition.make()` in [AppComposition.swift](../Sources/NikoMusicHub/AppComposition.swift) | Builds every store and service, the archive view model, the feature list and the `ToolRegistry` once, before any scene |
| Scenes | `NikoMusicHubApp.body` | Main window (`AppShellView`), Settings (`HubSettingsScene`), Help window, `MenuBarExtra`, menu command groups (`Sources/NikoMusicHub/Commands/`) |
| AppKit delegate | `AppDelegate` in the same file | Quit contract ([ADR 019](decisions/019-running-work-and-quit.md)), Dock menu, DEBUG smoke commands |
| Launch switches | [MusicHubRuntimeEnvironment.swift](../Sources/AppCore/Environment/MusicHubRuntimeEnvironment.swift) | The `NIKO_MUSIC_HUB_*` variables (fixture root, dry-run open, settings suite, E2E smoke, dev tool), read once at composition |
| CLI | [NikoMusicHubCLI/main.swift](../Sources/NikoMusicHubCLI/main.swift) | `export-index`, `export-diagnostics` over `NikoMusicCore` |
| Core self-test | [NikoMusicCoreSelfTest/main.swift](../Sources/NikoMusicCoreSelfTest/main.swift) | Fixture scan check; read-only counts on a real root |
| Gates and dev loop | `script/ci.sh`, `script/e2e_user_smoke.sh`, `script/dev.sh` | See [Tests and gates](#tests-and-gates-observed) and [local-dev-flow.md](local-dev-flow.md) |
| Release | `script/release-all.sh` | See [release.md](release.md) |

## Modules (observed)

Line counts are Swift source lines at the commit above, for orientation only.

| Target | Responsibility | Start reading | Tests |
| --- | --- | --- | --- |
| `NikoMusicCore` (18.7k) | Archive domain: scan, preview ranking, search, browse rules, path safety, opening, SQLite stores, Project Vault engines. No UI. | `Scanning/CubaseArchiveScanner.swift` (`MusicArchiveScanner`), `Domain/Song.swift`, `Safety/PathSafety.swift`, `Persistence/SQLiteArchiveDatabase.swift` | `NikoMusicCoreTests` |
| `AppCore` (16.1k) | Shell kit (tool seam, `ToolContext`, settings, jobs and quit, Output Inbox, helper tools, router, design system) **and** the Project Vault runtime | `Features/ToolFeature.swift`, `Services/ToolContext.swift`, `Shell/HubShellSession.swift`, `ProjectVault/LiveProjectVaultRuntime.swift` | `AppCoreTests` |
| `FeatureArchiveBrowser` (19.2k) | Board, list, song detail, preview player, metadata edits, Project Vault UI and queue | `ArchiveBrowserFeature.swift`, `ArchiveBrowserViewModel.swift`, the four coordinators in [architecture.md](architecture.md#featurearchivebrowser-swiftui-feature) | `FeatureArchiveBrowserTests` |
| `FeatureAudioConverter` (2.7k) | Batch WAV conversion: AVFoundation first, FFmpeg fallback | `BatchAudioConversionUseCase.swift`, `AudioConversionPipeline.swift` | `FeatureAudioConverterTests` |
| `FeatureAudioRecorder` (4.4k) | System-audio capture to WAV | `AudioCapturePort.swift`, `CoreAudioTapAdapter.swift` | `FeatureAudioRecorderTests` |
| `FeatureDownloader` (3.1k) | yt-dlp downloads | `DownloaderUseCase.swift`, `YtDlpDownloader.swift` | `FeatureDownloaderTests` |
| `FeatureStemSeparation` (2.1k) | demucs-mlx stems; YouTube input through the Downloader | `StemSeparationService.swift`, `YouTubeStemSeparationWorkflow.swift` | `FeatureStemSeparationTests` (Swift Testing) |
| `FeatureBPMTapper` (1.1k) | Tap tempo | `TempoEstimator.swift` | `FeatureBPMTapperTests` |
| `AppUpdates` (0.4k) | Sparkle updater, isolated | `AppUpdateController.swift` | `AppUpdatesTests` |
| `NikoMusicHub` (5.9k) | App target: composition, shell view, menus, Settings, Dev tool, DEBUG smoke commands | `AppComposition.swift`, `AppShell/AppShellView.swift` | source guards in `AppCoreTests` |

Dependencies, as declared in [Package.swift](../Package.swift):

```text
NikoMusicHub ──► AppUpdates, every Feature*, AppCore, NikoMusicCore
Feature*     ──► AppCore ──► NikoMusicCore
FeatureStemSeparation ──► FeatureDownloader      (the one feature → feature edge)
AppUpdates   ──► AppCore, Sparkle 2.9.6 (pinned exactly)
NikoMusicHubCLI, NikoMusicCoreSelfTest ──► NikoMusicCore
```

A feature is a `ToolFeature` value (metadata plus `makeView(context:)`). Each feature keeps a private
`Session` that creates its view model once, so a tab switch reuses it; `ToolPaneCache` keeps built panes
mounted.

## Main flows (observed)

Hops in call order. Ownership detail is in [architecture.md](architecture.md).

### Launch

1. `NikoMusicHubApp.init` applies `-ui-tool`, then calls `AppComposition.make()`.
2. `make()` opens one `SQLiteArchiveDatabase` and five stores on it. A store that fails becomes a
   `PersistenceIssue` banner, not a crash.
3. It builds the one `ToolContext`, then `ArchiveBrowserViewModel`, then `HubShellSession`, the feature
   list and the `ToolRegistry`. Store and registry failures go to `AppShellView` as `persistenceIssues`.
4. `shellSession.restoreSelectedToolID(registry:)` picks the launch tool before any scene exists.
5. `AppShellView` mounts the selected pane through `ToolPaneCache`.

### Find a song and open its project

1. `ArchiveBrowserViewModel.init` loads roots (`+Roots.swift`), then the cached snapshot
   (`loadCachedIndexIfAvailable` → `ArchiveCatalogCoordinator.loadCachedSongsReportDetached` →
   `SQLiteArchiveIndexStore.loadLatest`), then starts a background scan when it has a root watcher and no
   fixture root.
2. Root changes and `FSEventsArchiveRootWatcher` events reach `ArchiveScanOrchestrator`, which runs
   `MusicArchiveScanner` off the main actor (full or incremental). A result whose root generation is stale
   is dropped.
3. `ArchiveCatalogCoordinator` merges stored user metadata (`ArchiveMetadataMerger`). Scans never write
   metadata.
4. `applyCatalogScanUpdate` (`+ScanHost.swift`) applies `.rescan` through `applyCatalogEdit(_:)`
   (`ArchiveBrowserViewModel.swift`), which projects the result, writes `SongCatalog` and runs
   `ArchiveBrowseProjection` and `MusicSearchIndex`; `ArchiveMetadataEditingCoordinator.scheduleIndexPersist`
   saves the snapshot.
5. Open: `openLatestCPR(for:)` (`+Exports.swift`) checks the Vault block, then
   `MusicItemOpener.openLatestCPR(for:dryRun:allowedRoots:)` resolves the file with `PathSafety` and calls
   the injected `WorkspaceOpening` (nothing in dry-run).

### Run a tool and deliver its output

`view → view model → use case or service → adapter (AVFoundation, ffmpeg, yt-dlp, demucs-mlx, CoreAudio)`,
then the run's `ToolOutputDestination` (folder and guard from one settings read) admits the folder and the result goes to `OutputInboxStore`. Helpers run
through `ExternalProcessRunning` in their own process groups. The layers differ per tool:

| Tool | Runs as | Output guard in | Inbox write in |
| --- | --- | --- | --- |
| WAV Converter | own `Task` + extra source `converter` | `BatchAudioConversionUseCase`, from its run snapshot | `BatchAudioConversionUseCase` |
| Downloader | `JobRunner` job (+ extra source `downloadStart` for the title lookup) | `DownloaderViewModel` (`ToolOutputDestination.load`) | `DownloaderViewModel`, after it observes the job |
| Stem Separation | `JobRunner` job | `StemSeparationViewModel` loads it into the request; `StemSeparationService` admits the run folder | `StemSeparationService` |
| Audio Recorder | own `Task` + extra source `audioRecorder` | `ToolOutputDestination.load` / `RecordSystemAudioUseCase` | `AudioRecorderViewModel.finalizeRecording` |

### Project Vault: archive, restore, recover

1. A Done drop, the Done command or Archive Now calls `startBoundArchiveCapture`
   (`+ProjectVaultArchive.swift`). It captures a `ProjectVaultArchiveAuthorization` from the runtime
   **before** `ProjectVaultDoneChoiceSheet` opens. "Keep a verified copy" downgrades that same token to
   copy-only.
2. `ProjectVaultOperationCoordinator.enqueue` runs one operation at a time, rejects duplicates and retries
   a failed Done at most 3 times, copy-only.
3. `LiveProjectVaultRuntime` (actor, AppCore) takes the mutation lease (in-actor token plus a cross-process
   `flock`), re-checks the token against the live source, reconciles project identity (`+Catalog.swift`),
   builds the write and removal admissions (`+Admission.swift`) and creates a `LocalVaultTransferEngine`.
4. `LocalVaultTransferEngine` (actor, Core) stages a copy, verifies its `VaultManifest`, waits for
   durability (`ArchiveStorageProvider.waitUntilDurable`: `LocalVaultDurabilityBarrier` for a local folder,
   File Provider sync for a cloud folder), promotes the generation, and removes the active copy only with a
   removal token and fresh evidence. Each phase is saved in `SQLiteVaultTransferStore`, the authoritative
   journal.
5. Restore: `ProjectVaultRestoreSheet` → `restoreAndOpen` in the runtime (pins Keep Local first) →
   `LocalVaultRestoreEngine` (materialize, verify, copy, promote, save the location, open through
   `SafeVaultProjectOpener`).
6. Recover: the view model calls `recoverAtLaunch()` at launch and after settings changes;
   `ArchiveVaultObservation.scheduleRecovery` repeats it with a 30 s backoff. Launch recovery never
   deletes. Settings exports and imports a metadata recovery bundle (`ProjectVaultRecoveryService`).
7. Copy-only Done archiving also starts without a dialog: `enqueueDoneVaultProjectsIfNeeded`
   (`+ProjectVault.swift`) runs after each successful snapshot refresh and queues every Done song that has
   no transfer, is not Keep Local, not busy and not waiting for an identity review.

`NikoMusicCore/Vault` does every file operation and takes each policy decision as an injected admission
closure. `AppCore/ProjectVault` turns settings, Keep Local, Emergency Stop, capacity and the bound token
into those closures; it imports neither SwiftUI nor AppKit.

### Quit with running work

1. Work registers with `ShellJobStatusCenter`: `JobRunner` jobs automatically, everything else through
   `setExtraJob` (converter, recorder take, helper install, download start, archive scan, Vault queue).
2. `applicationShouldTerminate` asks `HubTerminationCoordinator`, which reads `quitBlockingWork`, shows one
   alert, cancels on confirm and replies when the work has unwound or after 5 s.
3. `applicationWillTerminate` reaps leftover helper process groups (`LiveProcessGroupRegistry`).

## State owners (observed)

| State | Owner | Persisted in |
| --- | --- | --- |
| Selected tool, panels, Set Up sheet | `HubShellSession` (AppCore) | `PreferenceStore` keys `hub.shell.*` |
| Back/forward | `HubNavigationHistory`, one instance shared by the shell and the archive | memory |
| Durable settings (music roots, output folder, Vault, helpers) | `SettingsStore` → `UserDefaultsSettingsStore`; display mirror `AppSettingsObserver` | UserDefaults key `nikoMusicHub.settings` (JSON) |
| Archive song catalog (scan baseline, visible list, id index) | `SongCatalog`, written only by `ArchiveBrowserViewModel.applyCatalogEdit(_:)` | snapshot in `SQLiteArchiveIndexStore` |
| Archive scan list (the folders the archive scans) | the settings store; edited only through `ArchiveScanList` (AppCore); the archive follows `appSettings` ([architecture.md § Archive scan list](architecture.md#archive-scan-list)) | settings JSON in UserDefaults |
| Loaded roots, selection, browse inputs | `ArchiveBrowserViewModel` | memory |
| Archive page (`viewMode`, `listShowsDetail`) | `ArchiveBrowserViewModel`; views call intents ([architecture.md § Archive page state](architecture.md#archive-page-state)) | memory; the route is recorded in `HubNavigationHistory` |
| User metadata (titles, notes, stages, collaborators) | `ArchiveMetadataEditingCoordinator` → `SQLiteSongUserMetadataStore`, `SQLiteCollaboratorStore` | `archive-index.sqlite` |
| Archive footer (message and warning) | `ArchiveFooterStatus`, held as `ArchiveBrowserViewModel.footer` | memory |
| Keep Local pins | `KeepLocalPins` over `VaultSettings.keepLocalProjectIDs` ([ADR 021](decisions/021-keep-local-pin-format.md)) | settings JSON in UserDefaults |
| Vault queue, retries, capacity | `ProjectVaultOperationCoordinator` | memory; the journal is authoritative |
| Vault presentation and automatic recovery | `ArchiveVaultObservation` | derived |
| Vault transfers and project identity | `LiveProjectVaultRuntime` (actor) → `SQLiteVaultTransferStore`, `SQLiteProjectCatalogStore` | `archive-index.sqlite` |
| Preview playback | `ArchivePreviewSession.shared`, `ArchivePlaybackCoordinator.shared` (singletons) | memory |
| Running work | `JobRunner`, merged with extra sources in `ShellJobStatusCenter` | memory |
| Output Inbox | `JSONOutputInboxStore` | `output-inbox.json` |
| A tool page's list of its own outputs | `ToolRecentOutputs` (AppCore), held by the tool's view model | derived from `output-inbox.json` |
| Cross-tool requests | `QuickAccessRouter` (one-shot values) | memory |
| Helper status (yt-dlp, FFmpeg, demucs-mlx) | `HelperToolHealth`, one per app in `ToolContext` ([architecture.md § Helper tools](architecture.md#helper-tools)) | memory; helper paths in the settings JSON |

App data lives in `~/Library/Application Support/Niko Music Hub/`, or in `Isolated/<suite>/` below it when
`NIKO_MUSIC_HUB_SETTINGS_SUITE` is set (`AppPaths` in `AppComposition.swift`).

## Seams (observed)

Protocols with a production adapter and a test adapter, so behavior can be replaced without editing the
caller.

| Seam | Production adapter | Replaced in tests to |
| --- | --- | --- |
| `ToolFeature` | the seven feature structs | register fakes in `FeatureRegistryTests` |
| `SettingsStore`, `PreferenceStore` | `UserDefaultsSettingsStore`, `UserDefaultsPreferenceStore` | use in-memory stores |
| `OutputInboxStore` | `JSONOutputInboxStore` | capture handoffs |
| `JobRunning` | `JobRunner` | control job timing |
| `ExternalProcessRunning`, `StreamingExternalProcessRunning` | `FoundationExternalProcessRunner` | script helper output and exits |
| `WorkspaceOpening` | the AppKit openers in the app target | record open/reveal calls |
| `ArchiveRootWatching` | `FSEventsArchiveRootWatcher` | `TestArchiveRootWatcher`, `NoopArchiveRootWatcher` |
| `ArchiveIndexStoring`, `SongUserMetadataStoring` | the SQLite stores | inject failures and corruption |
| `ProjectVaultOperating` | `LiveProjectVaultRuntime` | fake runtimes with entry gates |
| `ArchiveStorageProvider` | `LocalFolderArchiveStorage`, `FileProviderArchiveStorage` | simulate providers |
| `AudioCapturePort`, `StemSeparationBackend`, `AudioConverting` | CoreAudio, demucs-mlx, native/FFmpeg adapters | mocks and fixtures |

## Tests and gates (observed)

- One test target per source target; `FeatureStemSeparationTests` uses Swift Testing, the others XCTest.
- Archive tests use the synthetic archive in `Fixtures/CubaseArchive/`, generated by
  `script/fixtures/generate_cubase_archive_fixtures.sh`. Vault tests build temporary roots
  (`FriendsWorkflowFixture`, `ProjectVaultSyntheticFixtures`).
- Source guards in `Tests/AppCoreTests/*SourceTests.swift` read the source text and enforce the rules in
  [AGENTS.md](../AGENTS.md#rules-and-what-enforces-them): module boundaries, design contract, SwiftUI state
  ownership, output guard, real-defaults access, count copy, package settings.
- `./script/ci.sh`: fixtures, strict build (`--explicit-target-dependency-import-check error`,
  warnings as errors), `swift test` minus host-only CoreAudio tests, recorder gate, UI-probe self-test,
  `NikoMusicCoreSelfTest`, CLI export smoke and refusal, release-engineering tests.
- `./script/e2e_user_smoke.sh`: builds the app and drives it with a fixture root, dry-run open and an
  isolated settings suite. Needs Accessibility and Screen Recording. See [user-e2e.md](user-e2e.md).
- Release adds the exact-commit UAT record: [release-validation.md](release-validation.md),
  [ai-acceptance-testing.md](ai-acceptance-testing.md).

## Intended structure

These rules are documented and, where named, enforced. The full table is in
[AGENTS.md](../AGENTS.md#rules-and-what-enforces-them).

| Rule | Source | Enforced by |
| --- | --- | --- |
| Core has no UI frameworks; feature modules are independent except Stems → Downloader | [ADR 020](decisions/020-module-boundary-checks.md) | `ModuleBoundarySourceTests`, strict import check |
| Archive access is read-only; writes outside a confirmed Vault transfer are refused | [architecture.md § Safety](architecture.md#safety-architecture) | `ReadOnlyArchivePolicy`, `PathSafety`, `OutputGuardSourceTests` |
| Every feature registers through `ToolFeature`; the archive is not special | [architecture.md § Principles](architecture.md#principles) | judgment (see gap 1) |
| One registry of running work; quit reads it | [ADR 019](decisions/019-running-work-and-quit.md) | `HubTerminationSourceTests`, `ShellJobStatusCenterTests` |
| Keep Local pins are checked and written only through `KeepLocalPins`; the stored format stays | [ADR 021](decisions/021-keep-local-pin-format.md) | raw set `internal` to AppCore, `KeepLocalPinsSourceTests`, `KeepLocalPinsTests` |
| A tool run gets its output folder and guard from one `ToolOutputDestination` | [architecture.md § Tool output destination](architecture.md#tool-output-destination) | `OutputGuardSourceTests` (guard builders listed), `ToolOutputDestinationTests` |
| Archive views state intent; only the view model writes the archive page, and the song detail uses the status gate the edit coordinator enforces | [architecture.md § Archive page state](architecture.md#archive-page-state) | `ArchiveViewIntentSourceTests` |
| The archive song catalog is written only through `applyCatalogEdit(_:)` | [architecture.md § Archive song catalog](architecture.md#archive-song-catalog) | the compiler (`songCatalog`'s setter is private to its file), `SongCatalogTests`, `ArchiveCatalogEditTests` |
| A tool page reads its recent outputs only through `ToolRecentOutputs`, off the main actor | [architecture.md § Tool recent outputs](architecture.md#tool-recent-outputs) | `HandoffSurfacingSourceTests`, `ToolRecentOutputsTests` |
| The `App` observes only scene-structural state; one owner for selection | [AGENTS.md](../AGENTS.md#swiftui-state-ownership-do-not-regress) | `SwiftUIStateOwnershipSourceTests` |
| One UI scaffold, header and chrome material | [design-contract.md](design-contract.md) | `HubDesignContractSourceTests` |
| The Vault runtime leaves `AppCore` once it gets its own target | [AGENTS.md § Architecture](../AGENTS.md#architecture) | none; no date or trigger |

## Where the code differs from the intent (observed)

1. **The archive feature is wired specially.** `AppComposition.make()` builds `ArchiveBrowserViewModel`
   before the registry and passes it to `AppShellView` (persistent player, Set Up's Choose Folder), the
   settings-repair handler and first-launch onboarding. The shell imports `FeatureArchiveBrowser` for
   `ArchivePersistentPlayerView`. The Settings scene no longer holds it (2026-10-23): Settings saves the scan
   list and the archive follows the store.
2. **`ToolContext.init` creates a new job center, settings observer, router and repair model** when a
   caller leaves them out. The two production callers are correct: `AppComposition` passes them all, and
   `ArchiveSmokeCommands` runs alone. (The second context and the hand-counted tool number went on
   2026-10-23.)
3. **Two ways to run work.** Downloader and Stem Separation use `JobRunner`; the converter, recorder,
   helper installs, archive scan and Vault queue run their own tasks and register as extra sources.
   ADR 019 documents the registry, not which way a new tool should choose.
4. **The inbox handoff sits at a different layer per tool** (table above). Admission is one rule since
   2026-10-22: every run admits through one `ToolOutputDestination`. The handoff differences are mostly
   intended ([architecture.md § Tool output destination](architecture.md#tool-output-destination)). The
   Downloader's inbox write depends on the view model observing the job.
5. **Some dependencies are global, not injected:** `ArchivePreviewSession.shared`,
   `ArchivePlaybackCoordinator.shared`, `AudioCaptureActivity.shared` and `LiveProcessGroupRegistry.shared`.
   (Helper consumers share one `HelperToolLocator` through `HelperToolHealth` since 2026-10-23.)
6. **`ArchiveBrowserViewModel` is one type in 22 files** (the main file plus 21 `+*.swift` extensions,
   4,615 lines; the footer rules moved out to `ArchiveFooterStatus` on 2026-10-22, the song lists to `SongCatalog`
   on 2026-10-23). Four owners were extracted (scan orchestrator, catalog, metadata editing, Vault queue and
   observation); the extensions still share one set of state. The song catalog has one writer since 2026-10-23,
   but the root reset still resets about 35 other properties by hand.
7. **Test harness code ships in product modules.** `ArchiveUserFlowSmoke*.swift` (FeatureArchiveBrowser)
   and the smoke commands in `Sources/NikoMusicHub/` are `#if DEBUG`, except the scenario structs after
   the `#endif` in `ArchiveUserFlowSmokeScenarios.swift`. `DevToolFeature` always compiles and is shown
   only with `NIKO_MUSIC_HUB_SHOW_DEV_TOOL=1`.
8. **The "Archive automatically" switch starts no background archiving.** Its text in
   `ProjectVaultSettingsView.swift` and [vault-durability.md](vault-durability.md) describe archiving after
   inactivity or when space runs low. No production code builds a background (`.policy`) candidate for
   `VaultAutomationScheduler`; the only caller passes `.workflowDone`. The setting is read by diagnostics,
   the login-item warning, settings repair and `ProjectVaultRolloutPolicy.permitsActiveCopyRemoval`, which
   has no production caller.
9. **The Vault state machine is not the only writer of states.** `LocalVaultTransferEngine` sets
   `.archiveVerified` and `.recoveryRequired` directly and rewinds states in launch recovery;
   `LocalVaultRestoreEngine.advance` writes restore phases without a transition check. Vault folder names
   (`.niko-staging`, `generations/…`, `.niko-recovery`) are repeated in the engines, the runtime and the
   archive UI.

Documents that disagree with the code:

- [vault-durability.md § Capabilities note](vault-durability.md#capabilities-note) says no production code
  branches on `waitsForDurability`. `LocalVaultTransferEngine` branches on it before removal and when it
  retires survivors.
- [vault-durability.md](vault-durability.md) (summary list) describes background scheduling that is not
  wired (gap 8).

## Open questions

1. Settled on 2026-10-23: the stored settings own the scan list, `ArchiveScanList` edits it, and the archive
   follows `appSettings` ([architecture.md § Archive scan list](architecture.md#archive-scan-list)). One
   `ToolContext` serves the launch. The archive view model stays built by the composition for the shell.
2. Which layer owns the inbox handoff for a new tool, and should a new tool use `JobRunner` or an extra
   source? (Admission is settled: one `ToolOutputDestination` per run.)
3. What triggers moving the Project Vault runtime out of `AppCore`?
4. Should preview playback be injected instead of reached through singletons?
5. Is background Vault archiving (inactivity, low space) still planned? If yes, it needs wiring; if no,
   the Settings switch text and vault-durability.md need to change (gap 8).
6. Should every transfer and restore state change go through `ProjectVaultStateMachine` (gap 9)?
7. ADRs 001–016 are not in the public tree. Are they retired, or private planning history?
8. `docs/architecture.md` and this map are not in the source-sale export list (`script/export-source-sale.sh`),
   although `README.md` links `docs/architecture.md`. Is that intended?
9. Not verified at runtime: in E2E smoke mode the production archive view model probably exists beside
   the smoke's own view models, because `AppComposition.make()` runs before
   `applicationWillFinishLaunching`.
10. Board and list cards decide whether to offer a status change from the card-state policy alone, not from
    `canMutateWorkflowStatus(for:)`. From the code, a transfer in state `superseded` on a song that keeps its Active
    folder shows a card that offers a change the edit coordinator refuses. Should the card presentation carry the
    full gate?

## Check baseline (2026-10-22)

`./script/ci.sh` at `3ace650`, run from Terminal.app: **exit 0, no failures.**

- XCTest: 2,800 tests run, 8 skipped (opt-in live and hardware tests), 0 failures. Swift Testing: 93 tests
  in 9 suites passed. Recorder gate, UI-probe self-test, core self-test, CLI export and refusal smokes,
  and the release and source-distribution script tests passed.
- `ci.sh` skips the host-only CoreAudio capture tests by design.
- Not run: `./script/e2e_user_smoke.sh` (drives the UI and needs Accessibility; this change is
  documentation only).
- In an agent shell at utility QoS, four recorder probe tests can fail on unchanged code; run `ci.sh`
  from Terminal.app for a trustworthy result.

## Keeping this map current

Update this page in the same commit as a change that adds a module or a module edge, moves a state
owner, changes a main flow or closes an open question. Update the "Last verified" line when you
re-check it.
