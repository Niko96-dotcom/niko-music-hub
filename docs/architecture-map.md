# Architecture map — Niko Music Hub

Last verified: 2026-10-22 at `3ace650` (source read); modules, dependencies and the Vault flow re-checked on
2026-10-25 at the commit that adds `ProjectVaultRuntime` (parent `1b2caea`); the archive state owners, flows and
gap 6 re-checked on 2026-10-25 at `d55a7a3`. Latest `./script/ci.sh` result: [Check baseline](#check-baseline-2026-10-25)

Start here. This page names the entry points, modules, main flows, state owners, seams and gates, and
links to the documents that hold the detail. It does not repeat them.

Each section says what kind of statement it makes:

- **Observed**: read in the source at the commit above.
- **Intended**: a documented rule; the enforcer is named where one exists.
- **Open**: not decided, or not verified.

Detail lives in [architecture.md](architecture.md) (owners, safety, Project Vault),
[design-contract.md](design-contract.md) (UI), [decisions/](decisions/) (ADRs 017–022),
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

Line counts are Swift source lines at the commit above, for orientation only; `AppCore` and `ProjectVaultRuntime`
were recounted on 2026-10-25, when the runtime moved out of `AppCore`.

| Target | Responsibility | Start reading | Tests |
| --- | --- | --- | --- |
| `NikoMusicCore` (18.7k) | Archive domain: scan, preview ranking, search, browse rules, path safety, opening, SQLite stores, Project Vault engines. No UI. | `Scanning/CubaseArchiveScanner.swift` (`MusicArchiveScanner`), `Domain/Song.swift`, `Safety/PathSafety.swift`, `Persistence/SQLiteArchiveDatabase.swift` | `NikoMusicCoreTests` |
| `AppCore` (11.8k) | Shell kit only (tool seam, `ToolContext`, settings, jobs and quit, Output Inbox, helper tools, router, design system); [ADR 022](decisions/022-appcore-scope-and-vault-runtime-target.md) says what belongs here | `Features/ToolFeature.swift`, `Services/ToolContext.swift`, `Shell/HubShellSession.swift` | `AppCoreTests` |
| `ProjectVaultRuntime` (5.0k) | Project Vault runtime: the runtime actor, admissions, bound archive token, capacity, recovery bundle, presentation, Vault root pairing. No UI frameworks. | `LiveProjectVaultRuntime.swift`, `ProjectVaultOperating.swift`, `ProjectVaultArchiveAuthorization.swift` | `ProjectVaultRuntimeTests` |
| `FeatureArchiveBrowser` (19.2k) | Board, list, song detail, preview player, metadata edits, Project Vault UI and queue | `ArchiveBrowserFeature.swift`, `ArchiveBrowserViewModel.swift` (the composition), its state owners and coordinators in [architecture.md](architecture.md#featurearchivebrowser-swiftui-feature) | `FeatureArchiveBrowserTests` |
| `FeatureAudioConverter` (2.7k) | Batch WAV conversion: AVFoundation first, FFmpeg fallback | `BatchAudioConversionUseCase.swift`, `AudioConversionPipeline.swift` | `FeatureAudioConverterTests` |
| `FeatureAudioRecorder` (4.4k) | System-audio capture to WAV | `AudioCapturePort.swift`, `CoreAudioTapAdapter.swift` | `FeatureAudioRecorderTests` |
| `FeatureDownloader` (3.1k) | yt-dlp downloads | `DownloaderUseCase.swift`, `YtDlpDownloader.swift` | `FeatureDownloaderTests` |
| `FeatureStemSeparation` (2.1k) | demucs-mlx stems; YouTube input through the Downloader | `StemSeparationService.swift`, `YouTubeStemSeparationWorkflow.swift` | `FeatureStemSeparationTests` (Swift Testing) |
| `FeatureBPMTapper` (1.1k) | Tap tempo | `TempoEstimator.swift` | `FeatureBPMTapperTests` |
| `AppUpdates` (0.4k) | Sparkle updater, isolated | `AppUpdateController.swift` | `AppUpdatesTests` |
| `NikoMusicHub` (5.9k) | App target: composition, shell view, menus, Settings, Dev tool, DEBUG smoke commands | `AppComposition.swift`, `AppShell/AppShellView.swift` | source guards in `AppCoreTests` |

Dependencies, as declared in [Package.swift](../Package.swift):

```text
NikoMusicHub ──► AppUpdates, every Feature*, ProjectVaultRuntime, AppCore, NikoMusicCore
Feature*     ──► AppCore ──► NikoMusicCore
FeatureArchiveBrowser ──► ProjectVaultRuntime ──► AppCore, NikoMusicCore   (ADR 022)
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

1. `ArchiveBrowserViewModel.init` loads roots (`ArchiveLibraryModel.loadRootsFromSettings`), then the cached snapshot
   (`loadCachedIndexIfAvailable` → `ArchiveCatalogCoordinator.loadCachedSongsReportDetached` →
   `SQLiteArchiveIndexStore.loadLatest`), then starts a background scan when it has a root watcher and no
   fixture root.
2. Root changes and `FSEventsArchiveRootWatcher` events reach `ArchiveScanOrchestrator`, which runs
   `MusicArchiveScanner` off the main actor (full or incremental). A result whose root generation is stale
   is dropped.
3. `ArchiveCatalogCoordinator` merges stored user metadata (`ArchiveMetadataMerger`). Scans never write
   metadata.
4. `applyCatalogScanUpdate` (`+Scan.swift`) applies `.rescan` through `applyCatalogEdit(_:)`
   (`ArchiveBrowserViewModel.swift`), which projects the result, writes `SongCatalog` and has `ArchiveBrowseModel`
   run `ArchiveBrowseProjection` and `MusicSearchIndex`; `ArchiveMetadataEditingCoordinator.scheduleIndexPersist`
   saves the snapshot.
5. Open: `ArchiveFileAccessModel.openLatestCPR(for:)` checks the Vault block, then
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

A new tool runs as a `JobRunner` job. The converter, the recorder take and the download's title lookup are named
exceptions with their reasons ([architecture.md § How a tool runs its work](architecture.md#how-a-tool-runs-its-work)).

### Project Vault: archive, restore, recover

1. A Done drop, the Done command or Archive Now calls `startBoundArchiveCapture`
   (`+ProjectVaultArchive.swift`). It captures a `ProjectVaultArchiveAuthorization` from the runtime
   **before** `ProjectVaultDoneChoiceSheet` opens; `ArchiveVaultDialogsModel` lets only the current capture present. "Keep a verified copy" downgrades that same token to
   copy-only.
2. `ProjectVaultOperationCoordinator.enqueue` runs one operation at a time, rejects duplicates and retries
   a failed Done at most 3 times, copy-only.
3. `LiveProjectVaultRuntime` (actor, `ProjectVaultRuntime`) takes the mutation lease (in-actor token plus a cross-process
   `flock`), re-checks the token against the live source, reconciles project identity (`+Catalog.swift`),
   builds the write and removal admissions (`+Admission.swift`) and creates a `LocalVaultTransferEngine`
   through `makeTransferEngine`, which passes the runtime's stores, clock and recovery policy.
4. `LocalVaultTransferEngine` (actor, Core) stages a copy, verifies its `VaultManifest`, waits for
   durability (`ArchiveStorageProvider.waitUntilDurable`: `LocalVaultDurabilityBarrier` for a local folder,
   File Provider sync for a cloud folder), promotes the generation, and removes the active copy only with a
   removal token and fresh evidence. Each phase change is checked against `ProjectVaultStateMachine` and saved in
   `SQLiteVaultTransferStore`, the authoritative journal ([architecture.md § Vault state changes](architecture.md#vault-state-changes)).
5. Restore: `ProjectVaultRestoreSheet` → `restoreAndOpen` in the runtime (pins Keep Local first) →
   `LocalVaultRestoreEngine` from `makeRestoreEngine` (materialize, verify, copy, promote, save the
   location, open through `SafeVaultProjectOpener`).
6. Recover: the view model calls `recoverAtLaunch()` at launch and after settings changes;
   `ArchiveVaultObservation.scheduleRecovery` repeats it with a 30 s backoff. Launch recovery never
   deletes, and it first hands every interrupted removal to the person's review (`recoveryRequired`), whatever
   newer records or verified generations its project has. Until the person recovers that removal, launch, the timer
   and the person's Retry leave the project's other transfers as saved (`awaitsRemovalReview(_:)`, which also keeps
   them out of `nextAutomaticRecoveryDate()`); the song detail shows the removal first, and Recover marks those
   transfers `superseded`. Settings exports and imports a metadata recovery bundle (`ProjectVaultRecoveryService`).
7. Copy-only Done archiving also starts without a dialog: `enqueueDoneVaultProjectsIfNeeded`
   (`+ProjectVault.swift`) runs after each successful snapshot refresh and queues every Done song that has
   no transfer, is not Keep Local, not busy and not waiting for an identity review. This is the only
   automatic archiving; nothing archives on a timer, after inactivity or on low space.

`NikoMusicCore/Vault` does every file operation and takes each policy decision as an injected admission
closure. `ProjectVaultRuntime` turns settings, Keep Local, Emergency Stop, capacity and the bound token
into those closures; it imports neither SwiftUI nor AppKit. Every folder path inside the two Vault roots
comes from `VaultFolders` (Core); see [architecture.md § Vault folders](architecture.md#vault-folders).

### Quit with running work

1. Work registers with `ShellJobStatusCenter`: `JobRunner` jobs automatically, everything else through
   `setExtraJob` (converter, recorder take, helper install, download start, archive scan, Vault queue).
2. `applicationShouldTerminate` asks `HubTerminationCoordinator`, which reads `quitBlockingWork`, shows one
   alert, cancels on confirm and replies when the work has unwound or after 5 s.
3. `applicationWillTerminate` reaps leftover helper process groups in the app's one `LiveProcessGroupRegistry`,
   where every helper started through `ToolContext.processRunner` is recorded.

## State owners (observed)

| State | Owner | Persisted in |
| --- | --- | --- |
| Selected tool, panels, Set Up sheet | `HubShellSession` (AppCore) | `PreferenceStore` keys `hub.shell.*` |
| Back/forward | `HubNavigationHistory`, one instance shared by the shell and the archive | memory |
| Durable settings (music roots, output folder, Vault, helpers) | `SettingsStore` → `UserDefaultsSettingsStore`; display mirror `AppSettingsObserver` | UserDefaults key `nikoMusicHub.settings` (JSON) |
| Archive song catalog (scan baseline, visible list, id index) | `SongCatalog`, written only by `ArchiveBrowserViewModel.applyCatalogEdit(_:)` | snapshot in `SQLiteArchiveIndexStore` |
| Archive scan list (the folders the archive scans) | the settings store; edited only through `ArchiveScanList` (AppCore); the archive follows `appSettings` ([architecture.md § Archive scan list](architecture.md#archive-scan-list)) | settings JSON in UserDefaults |
| Loaded roots, their access, first-run state, scan state (scanning, scan error, diagnostics, root generation) | `ArchiveLibraryModel`, held as `ArchiveBrowserViewModel.library` | memory |
| Archive browse inputs and results (search text, shelf, filters, sort, filtered list, search index) | `ArchiveBrowseModel`, held as `ArchiveBrowserViewModel.browse` | memory |
| Archive page (`viewMode`, `listShowsDetail`) and the selected song | `ArchivePageModel`, held as `ArchiveBrowserViewModel.page`; views call intents ([architecture.md § Archive page state](architecture.md#archive-page-state)) | memory; the route is recorded in `HubNavigationHistory` |
| User metadata (titles, notes, stages, collaborators) | `ArchiveMetadataEditingCoordinator` → `SQLiteSongUserMetadataStore`, `SQLiteCollaboratorStore` | `archive-index.sqlite` |
| Archive footer (message and warning) | `ArchiveFooterStatus`, held as `ArchiveBrowserViewModel.footer` | memory |
| Keep Local pins | `KeepLocalPins` over `VaultSettings.keepLocalProjectIDs` ([ADR 021](decisions/021-keep-local-pin-format.md)) | settings JSON in UserDefaults |
| Vault queue, retries, capacity | `ProjectVaultOperationCoordinator` | memory; the journal is authoritative |
| Vault presentation, automatic recovery and the "Show archived" choice | `ArchiveVaultObservation` | derived; the choice in memory |
| Archive Vault dialogs (archive/Done confirmation and its authorization capture, restore sheet and progress, identity review, stop transfer, stopped for quit) | `ArchiveVaultDialogsModel`, held as `ArchiveBrowserViewModel.vaultDialogs` | memory |
| Vault transfers and project identity | `LiveProjectVaultRuntime` (actor) → `SQLiteVaultTransferStore`, `SQLiteProjectCatalogStore` | `archive-index.sqlite` |
| Vault transfer state, restore phase | the tables `ProjectVaultStateMachine` and `VaultRestorePhase.allowedNextPhases`; written only by each engine's `checkAndSave` and the restore reconcile ([architecture.md § Vault state changes](architecture.md#vault-state-changes)) | `vault_transfers`, `vault_restores` in `archive-index.sqlite` |
| Archive file access results (nearby open error, last dry-run path, last export paths) | `ArchiveFileAccessModel`, held as `ArchiveBrowserViewModel.fileAccess` | memory |
| Collaborator address book as the archive shows it, and a staged removal | `ArchiveAddressBookModel`, held as `ArchiveBrowserViewModel.addressBook`, over `SQLiteCollaboratorStore` | `archive-index.sqlite` |
| Archive intelligence (collaborator suggestions and their dismissals, duplicate hints, missing audio) | `ArchiveIntelligenceModel`, held as `ArchiveBrowserViewModel.intelligence` | memory |
| Archive song analysis (BPM/key of the main preview, the project's plug-ins) | `ArchiveSongAnalysisModel`, held as `ArchiveBrowserViewModel.songAnalysis`; follows each catalog change | memory |
| Preview playback | `ArchivePreviewSession`, held by `ArchiveBrowserViewModel.previewSession`; views get it by initializer ([architecture.md § Archive preview playback](architecture.md#archive-preview-playback)) | memory |
| Running work | `JobRunner`, merged with extra sources in `ShellJobStatusCenter`; each row's verb, Cancel help and cancel target come from its tool | memory |
| A tool page's Return and Esc keys | `HubInspectorPage` (`primaryKey`, `cancelKey`, otherwise the shell's Esc from `HubShellEscape`), bound only on the visible page; the Archive Browser, no `HubInspectorPage`, owns its keys in `ArchiveBrowserView` under the same rule ([architecture.md § Tool page keys](architecture.md#tool-page-keys)) | code |
| Tool order, the Settings row, which pane keeps Esc | each tool's `ToolMetadata` (`section`, `handlesEscape`), read through `ToolSection.sidebarOrder` and `InAppJobCancelRouting` ([architecture.md § Tool self-description](architecture.md#tool-self-description)) | code |
| Output Inbox | `JSONOutputInboxStore` | `output-inbox.json` |
| A tool page's list of its own outputs | `ToolRecentOutputs` (AppCore), held by the tool's view model | derived from `output-inbox.json` |
| Cross-tool requests | `QuickAccessRouter` (one-shot values) | memory |
| Helper status (yt-dlp, FFmpeg, demucs-mlx) | `HelperToolHealth`, one per app in `ToolContext` ([architecture.md § Helper tools](architecture.md#helper-tools)) | memory; helper paths in the settings JSON |
| Running helper process groups | one `LiveProcessGroupRegistry` from `AppComposition`, recorded by its one runner `ToolContext.processRunner`; the app delegate reaps it at quit ([ADR 019](decisions/019-running-work-and-quit.md)) | memory |
| Recording signal (a take pauses archive preview) | one `AudioCaptureActivity` from `AppComposition`, in `ToolContext.audioCaptureActivity`; the recorder sets it, the preview session observes it ([architecture.md § Archive preview playback](architecture.md#archive-preview-playback)) | memory |

App data lives in `~/Library/Application Support/Niko Music Hub/`, or in `Isolated/<suite>/` below it when
`NIKO_MUSIC_HUB_SETTINGS_SUITE` is set (`AppPaths` in `AppComposition.swift`).

## Seams (observed)

Protocols with a production adapter and a test adapter, so behavior can be replaced without editing the
caller.

| Seam | Production adapter | Replaced in tests to |
| --- | --- | --- |
| `ToolFeature` | the seven feature structs (their `ToolMetadata` gives the sidebar section and whether the pane keeps Esc) | register fakes in `FeatureRegistryTests` |
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
  `AppCoreTests` also imports the archive and recorder features and the Vault runtime for the cross-feature tests
  (the registry, Keep Local pins, the recording signal, settings with Vault refusals).
- Archive tests use the synthetic archive in `Fixtures/CubaseArchive/`, generated by
  `script/fixtures/generate_cubase_archive_fixtures.sh`. Vault tests build temporary roots
  (`FriendsWorkflowFixture`, `ProjectVaultSyntheticFixtures`).
- Source guards in `Tests/AppCoreTests/*SourceTests.swift` read the source text and enforce the rules in
  [AGENTS.md](../AGENTS.md#rules-and-what-enforces-them): module boundaries, design contract, SwiftUI state
  ownership, output guard, real-defaults access, count copy, package settings.
- `./script/ci.sh`: fixtures, clean strict build (`--explicit-target-dependency-import-check error`,
  warnings as errors, fails on any printed warning), `swift test` minus host-only CoreAudio tests,
  recorder gate, UI-probe self-test, `NikoMusicCoreSelfTest`, CLI export smoke and refusal,
  release-engineering tests.
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
| `AppCore` holds only the shell kit; a subsystem with its own state owners and rules, used only by one feature and the composition, gets its own target. `ProjectVaultRuntime` imports only `AppCore`, `NikoMusicCore` and system frameworks, and only the archive feature and the app import it | [ADR 022](decisions/022-appcore-scope-and-vault-runtime-target.md) | `ModuleBoundarySourceTests`, strict import check |
| Archive access is read-only; writes outside a confirmed Vault transfer are refused | [architecture.md § Safety](architecture.md#safety-architecture) | `ReadOnlyArchivePolicy`, `PathSafety`, `OutputGuardSourceTests` |
| Every feature registers through `ToolFeature`; the archive is not special | [architecture.md § Principles](architecture.md#principles) | judgment (see gap 1) |
| One registry of running work; quit reads it | [ADR 019](decisions/019-running-work-and-quit.md) | `HubTerminationSourceTests`, `ShellJobStatusCenterTests` |
| A tool runs work the person waits for as a `JobRunner` job; its own `Task` is view-local; work outside the runner is a named extra source | [architecture.md § How a tool runs its work](architecture.md#how-a-tool-runs-its-work) | `ToolWorkSourceTests` |
| A tool page binds Return and Esc only through `HubInspectorPage`; a page you left takes no key | [design-contract.md §4](design-contract.md#4-tool-pages--hubinspectorpage) | `HubDesignContractSourceTests`, `HubInspectorPageKeysTests` |
| Each built-in tool ID is defined once; shell code orders, routes and labels tools from their metadata and job rows, never by ID | [architecture.md § Tool self-description](architecture.md#tool-self-description) | `ToolIDSourceTests`, `ToolSectionTests`, `InAppJobCancelRoutingTests` |
| Keep Local pins are checked and written only through `KeepLocalPins`; the stored format stays | [ADR 021](decisions/021-keep-local-pin-format.md) | raw set `internal` to AppCore, `KeepLocalPinsSourceTests`, `KeepLocalPinsTests` |
| A tool run gets its output folder and guard from one `ToolOutputDestination` | [architecture.md § Tool output destination](architecture.md#tool-output-destination) | `OutputGuardSourceTests` (guard builders listed), `ToolOutputDestinationTests` |
| Archive views state intent; only `ArchivePageModel` writes the archive page, and the song detail and the cards use the status gate the edit coordinator enforces | [architecture.md § Archive page state](architecture.md#archive-page-state) | `private(set)` setters, `ArchiveViewIntentSourceTests`; `ArchiveVaultObservationTests` (each card offers a status change exactly when the gate accepts it) |
| The archive song catalog is written only through `applyCatalogEdit(_:)` | [architecture.md § Archive song catalog](architecture.md#archive-song-catalog) | the compiler (`songCatalog`'s setter is private to its file), `SongCatalogTests`, `ArchiveCatalogEditTests` |
| A tool page reads its recent outputs only through `ToolRecentOutputs`, off the main actor | [architecture.md § Tool recent outputs](architecture.md#tool-recent-outputs) | `HandoffSurfacingSourceTests`, `ToolRecentOutputsTests` |
| The `App` observes only scene-structural state; one owner for selection | [AGENTS.md](../AGENTS.md#swiftui-state-ownership-do-not-regress) | `SwiftUIStateOwnershipSourceTests` |
| One UI scaffold, header and chrome material | [design-contract.md](design-contract.md) | `HubDesignContractSourceTests` |

## Where the code differs from the intent (observed)

1. **The archive feature is wired specially.** `AppComposition.make()` builds `ArchiveBrowserViewModel`
   before the registry and passes it to `AppShellView` (persistent player, Set Up's Choose Folder), the
   settings-repair handler and first-launch onboarding. The shell imports `FeatureArchiveBrowser` for
   `ArchivePersistentPlayerView`. The Settings scene no longer holds it (2026-10-23): Settings saves the scan
   list and the archive follows the store.
2. **`ToolContext.init` creates a new job center, settings observer, router, repair model and recording
   signal** when a caller leaves them out. The two production callers are correct: `AppComposition` passes
   them all, and `ArchiveSmokeCommands` runs alone. (The second context and the hand-counted tool number went
   on 2026-10-23.)
3. Closed on 2026-10-25: one rule says how a tool runs its work. Work the person waits for is a `JobRunner` job
   (Downloader, Stem Separation); the converter, the recorder take, the download's title lookup, helper installs, the
   archive scan and the Vault queue are named extra sources, each with its reason, and `ToolWorkSourceTests` lists
   every `Task` a tool module creates ([architecture.md § How a tool runs its work](architecture.md#how-a-tool-runs-its-work)).
   The WAV Converter is the one tool run that could be a job and is not; the reason and what it would take are there.
   Still open: the Settings recovery export and import and the test restore run in unregistered tasks, so quit does
   not wait for them; the check lists them as that gap.
4. **The inbox handoff sits at a different layer per tool** (table above). Admission is one rule since
   2026-10-22: every run admits through one `ToolOutputDestination`. The handoff differences are mostly
   intended ([architecture.md § Tool output destination](architecture.md#tool-output-destination)). The
   Downloader's inbox write depends on the view model observing the job.
5. Closed on 2026-10-25: no dependency is global. `AppComposition` builds the one `LiveProcessGroupRegistry` and
   its runner, `ToolContext.processRunner` carries the runner to every helper, and the app delegate reaps that
   registry; no runner initializer has a default runner or registry (`HubTerminationSourceTests`). (Helper
   consumers share one `HelperToolLocator` through `HelperToolHealth` since 2026-10-23; preview playback belongs to
   the archive view model, and the recorder and the archive share one recording signal through `ToolContext`, since
   2026-10-24.)
6. Closed on 2026-10-25: `ArchiveBrowserViewModel` is the composition of state owners. Each owner holds one set of
   state with its rules and its own tests: `ArchiveBrowseModel`, `ArchivePageModel`, `ArchiveLibraryModel`,
   `ArchiveIntelligenceModel`, `ArchiveSongAnalysisModel`, `ArchiveAddressBookModel`, `ArchiveFileAccessModel`,
   `ArchiveVaultDialogsModel`, beside the earlier `ArchiveScanOrchestrator`, `ArchiveCatalogCoordinator`,
   `ArchiveMetadataEditingCoordinator`, `ProjectVaultOperationCoordinator` and `ArchiveVaultObservation`. The view
   model keeps the song catalog writer, the footer, the root reset (one call per owner, in a documented order) and
   the intents that cross owners, in 10 files (it was 22).
7. **Test harness code ships in product modules.** `ArchiveUserFlowSmoke*.swift` (FeatureArchiveBrowser)
   and the smoke commands in `Sources/NikoMusicHub/` are `#if DEBUG`, the scenario structs included since
   2026-10-25. `DevToolFeature` always compiles and is shown
   only with `NIKO_MUSIC_HUB_SHOW_DEV_TOOL=1`.
8. Closed on 2026-10-24: the "Archive automatically" switch, its steppers, the Vault login-item row and
   the unused background-scheduling code are gone. The only automatic archiving is the copy-only Done
   copy (main flow step 7; [architecture.md § Project Vault bound authorization](architecture.md#project-vault-bound-authorization)).
9. Closed on 2026-10-24: every transfer state and restore phase change goes through its table, and each engine's
   `checkAndSave` (plus the restore reconcile) is the only writer; an unlisted edge throws before anything is saved
   ([architecture.md § Vault state changes](architecture.md#vault-state-changes)).
10. Closed on 2026-10-24: a plain Esc on a tool page cancels what Edit ▸ Cancel cancels. AppKit offers a key
    without ⌘ to the menu only while no window is key, so the menu item never got it; the visible
    `HubInspectorPage` now binds the shell's Esc (`HubShellEscape`) while it has no enabled cancel key. Checked live
    on the WAV Converter (the second Esc stops the file in flight) and on Stem Separation
    ([architecture.md § Tool page keys](architecture.md#tool-page-keys)).

Documents that disagree with the code: none known. (Closed on 2026-10-25:
[vault-durability.md § Capabilities note](vault-durability.md#capabilities-note) now names the two places where
`LocalVaultTransferEngine` checks `waitsForDurability`.)

## Open questions

1. Settled on 2026-10-23: the stored settings own the scan list, `ArchiveScanList` edits it, and the archive
   follows `appSettings` ([architecture.md § Archive scan list](architecture.md#archive-scan-list)). One
   `ToolContext` serves the launch. The archive view model stays built by the composition for the shell.
2. Settled on 2026-10-25: a new tool runs its work as a `JobRunner` job, not an extra source, and writes its inbox
   handoff inside the job's operation, as Stem Separation does; the handoff stays in each tool (gap 3, gap 4,
   [architecture.md § How a tool runs its work](architecture.md#how-a-tool-runs-its-work)). Admission was settled
   before: one `ToolOutputDestination` per run.
3. Settled on 2026-10-25: a subsystem with its own state owners and rules, used only by one feature and the
   composition, gets its own target over `AppCore`. The Project Vault runtime met that test and is `ProjectVaultRuntime`;
   `AppCore` names no runtime type ([ADR 022](decisions/022-appcore-scope-and-vault-runtime-target.md)).
4. Settled on 2026-10-24: preview playback is injected. The archive view model owns the one session and views get
   it by initializer; the coordinator is gone ([architecture.md § Archive preview playback](architecture.md#archive-preview-playback)).
5. Settled on 2026-10-24: no background Vault archiving (inactivity, low space). Niko chose to remove the
   switch; the Done copy is the only automatic archiving (gap 8).
6. Settled on 2026-10-24: every transfer state change goes through `ProjectVaultStateMachine` and every restore phase
   change through `VaultRestorePhase`'s table; an unlisted edge fails closed (gap 9).
7. ADRs 001–016 are not in the public tree. Are they retired, or private planning history?
8. `docs/architecture.md` and this map are not in the source-sale export list (`script/export-source-sale.sh`),
   although `README.md` links `docs/architecture.md`. Is that intended?
9. Not verified at runtime: in E2E smoke mode the production archive view model probably exists beside
   the smoke's own view models, because `AppComposition.make()` runs before
   `applicationWillFinishLaunching`.
10. Settled on 2026-10-25: the card presentation carries the file-action block, and its `allowsWorkflowMutation`
    is the one status-change rule for the cards (menu, drag, VoiceOver) and `canMutateWorkflowStatus(for:)`
    ([architecture.md § Archive page state](architecture.md#archive-page-state)). The superseded example cannot
    happen in the app: `LiveProjectVaultRuntime.snapshots()` drops superseded transfers (checked live). The
    historical archive folder of a restored project still reads Active while the Vault holds it; unit-tested, not
    reached in a running app.

## Check baseline (2026-10-25)

`./script/ci.sh` at `8332bdb` (the 1.9.0 release preparation), run from Terminal.app: **exit 0, no failures.**

- XCTest: 2,978 tests run, 8 skipped (opt-in live and hardware tests), 0 failures. Swift Testing: 89 tests
  in 8 suites passed. Recorder gate, UI-probe self-test, core self-test, CLI export and refusal smokes,
  and the release and source-distribution script tests passed.
- `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` passed on the same files; production preferences unchanged.
- `ci.sh` skips the host-only CoreAudio capture tests by design.
- The first `ci.sh` run on these files stopped at the clean build: SwiftPM printed a package-cache warning
  (`'sparkle': skipping cache due to an error`), and `ci.sh` fails on any printed warning. The rerun was clean.
- In an agent shell at utility QoS, four recorder probe tests can fail on unchanged code; run `ci.sh`
  from Terminal.app for a trustworthy result.

## Keeping this map current

Update this page in the same commit as a change that adds a module or a module edge, moves a state
owner, changes a main flow or closes an open question. Update the "Last verified" line when you
re-check it.
