# Plan: One tool context; the store owns the archive's scan list

**Status:** Approved by Niko on 2026-10-23, including requirements 3, 4 and 6. In progress — see [Progress](#progress).  
**Date:** 2026-10-23  
**Source:** finding #7 of the 2026-10-22 architecture review ("Archive roots and the composition order"), with its
quick step 1 (delete `registeredToolCount`). It also settles open question 1 of
[architecture-map.md](../architecture-map.md#open-questions).  
**Scope:** `AppComposition`, `ToolContext`, the Dev Tool label, the shell's warning banner, the archive's root code
(`ArchiveBrowserViewModel+Roots.swift`, `+ProjectVault.swift`), Settings (Music archive and Project Vault panes),
the Set Up sheet, one new AppCore value module, their tests, the docs. No change to the Vault engines, the scanner,
the settings format, `VaultRootManager` or the design contract.

This plan keeps two kinds of statement apart. **Current** describes the code at `9db2010`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed). Find a step's
commit with `git log --grep='(roots step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `9db2010` (its commit message), no code commits since; no re-run |
| 1 One tool context | done | `git log --grep='(roots step 1)'` | strict build; `AppCoreTests` 813 (2 skipped), `FeatureArchiveBrowserTests` 662, converter 97, downloader 206 (2 skipped), stem 93 (Swift Testing), 0 failures; `archive-launch.swift` and `archive-tools.swift` typecheck |
| 2 One module edits the scan list | done | `git log --grep='(roots step 2)'` | strict build; `ArchiveScanListTests` 13, `FeatureArchiveBrowserTests` 662, AppCore `*SourceTests` 96, 0 failures; changed test expectations in revisions 2 to 5 |
| 3 The archive follows the store | not started | | |
| 4 Settings and Set Up use the store | not started | | |
| 5 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 2: one canonical spelling, owned by `ArchiveScanList`.** `resolvingSymlinksInPath` strips a leading
   `/private`, so the canonical form of `/private/var/…` is `/var/…`. `ArchiveBrowserViewModel.canonicalPath(for:)` and
   `bookmarkKey(for:)` (the same value) are gone; tests use `ArchiveScanList.canonicalPath(for:)`.
2. **Step 2: a failed save changes nothing.** Before, a failed root save still showed the folder until the next launch
   and kept the fresh bookmark in memory for a later `persistRoots()`. Now the archive reloads only after a successful
   save, so the folder does not show and the footer warning says why; the person adds it again.
   `testArchiveRootPersistenceFailureIsVisible` now expects no root, and
   `testPersistenceFailurePreservesActionableRecovery` repairs with a second Grant Access.
3. **Step 2: tests seed the store, not memory.** `testRemoveOneRootClearsCatalogAndPersistsRemainingRoot` and
   `testRemoveRootClearsRootBoundArchiveState` store their roots;
   `testSameFolderReauthorizationRepairsWhenRootsAlreadyContainsDuplicateCanonical` no longer seeds `roots` and
   bookmarks (the stored duplicate is the case). `testPartialSuccessPreservesAccessibleRootsAndBookmarkTokens` drops its
   in-memory token check; the stored token is still checked.
4. **Step 2: fixture runs keep the fixture root.** The fixture-root hook pins the loaded roots, so in a fixture run an
   add or a remove is saved but the board keeps the fixture (before, an add showed until relaunch). The in-app
   user-flow smoke's invalid-root check now seeds its two roots in memory, as its truncation check does, and no longer
   writes them into the run's settings. The live check of steps 2 to 4 uses a run without the hook (`first-run`
   profile and scratch folders). Requirement 8 holds for the E2E smoke, which adds no folder.
5. **Step 2: no "ordinary persist" left.** The two tests that called `persistRoots()` alone
   (`testVaultOffSameFolderPair…`, `testDisabledActiveSameFolderPair…`) make an unrelated folder add instead;
   `testRetryKeepsHealthyRootsAndBookmarkForRecoveredRoot` and `testUnresolvedActiveRootIsNotDuplicatedByRepeatedRootChanges`
   drop the call (retry writes nothing; remove saves itself).
6. **Step 2: every add saves and scans.** Adding a folder that is already listed refreshes its bookmark and scans
   (before: nothing). Adding a folder whose only record is disabled adds an enabled record and keeps the disabled one
   (before: the disabled record blocked the add, so nothing was stored).

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Stored roots | Every music root in the settings JSON, whatever its role or state | `AppSettings.musicRoots` (`StoredMusicRoot`) |
| Scan list | The stored roots the Archive Browser scans: enabled Scan-only roots, plus the Vault Active root while Vault is on; never the Vault Archive root | `filteredEffectiveScanRoots(from:)` (private, `+Roots.swift:396`) over `effectiveScanRoots` |
| Loaded roots | The folders the archive resolved from the scan list, with security-scoped access held | `ArchiveBrowserViewModel.roots`, `securityScopedRootAccesses` |
| Root inputs | The part of stored settings that decides the loaded roots: `musicRoots`, `vault.isEnabled`, `vault.activeRootID`, `vault.archiveRootID` | none |
| Root reload | Resolve the scan list, restart the folder watcher, keep or clear the catalog, scan | `loadRootsFromSettings()` plus each caller's own follow-up |

## Current architecture (observed at `9db2010`)

### Two tool contexts and a hand-counted tool number

`AppComposition.make()` builds `ToolContext` #1 (`AppComposition.swift:166-182`) because `ArchiveBrowserViewModel`
needs one (`:187-198`), and the archive's feature value needs the view model before the feature list and the
`ToolRegistry` exist (`:244-277`). A registry failure then appends a `PersistenceIssue`, so a second, otherwise
identical `ToolContext` is built for the shell (`finalContext`, `:283-299`). Two values follow from that order:

- `registeredToolCount` is counted by hand before the feature list exists (`:66-79`: 7, plus the Dev Tool, plus the
  design preview in DEBUG) and an `assert` compares it with `features.count` (`:260-264`). Its only reader is a Dev
  Tool label, `Text("Registered tools: …")` (`DevToolFeature.swift:79`). It is a required `ToolContext.init`
  argument, so 25 lines in 12 test and script files mention it: most pass a made-up number, and `ToolContextTests`
  reads it back.
- `persistenceIssues` (`ToolContext.swift:24`) is read only by the shell's warning banner (`AppShellView.swift:211,
  215, 237, 242`). The archive view model holds context #1, which lacks the registry issue, and never reads it.

`ToolContext.init` also creates a new job status center, settings observer, router and repair model when a caller
leaves them out (`ToolContext.swift:49-54, 65-70`). Two production callers exist: `AppComposition` passes all of
them; `ArchiveSmokeCommands.swift:49-60` is a standalone smoke run and relies on the defaults.

### The archive view model owns writing the scan list

Every in-process writer of the scan list goes through `ArchiveBrowserViewModel` or must call it afterwards:

| Writer | Today |
| --- | --- |
| Board: Add Folder, Grant Access (`ArchiveBrowserView.swift:627-674`) | `addRoots(_:bookmarksByURL:)` (`+Roots.swift:425`) |
| Set Up sheet: Choose Folder (`AppShellView.swift:271-274`) | `archiveViewModel.addRoot(_:)`; `HubSetupView` reads `archiveViewModel.roots` (`:78-81, 172`) |
| Settings > Music archive: Add, Remove (`SettingsView.swift:375-382`) | `archiveViewModel.addRoot(_:)`, `archiveViewModel.removeRoot(_:)`; the list shows `archiveViewModel.roots` (`:311`) |
| Settings > Project Vault: Active or Archive folder, Vault on/off, other Vault settings (`ProjectVaultSettingsView.swift:435-462`, `SettingsView.swift:391-397`) | `session.persistSettings`, then `archiveViewModel.applyProjectVaultSettingsChange()` (`+ProjectVault.swift:49-80`) |
| Settings repair (`AppComposition.swift:234-239`) | repair handler calls `archiveViewModel.applyRepairedSettings()` (`+Roots.swift:94`) |

So the Settings scene holds the archive view model (`NikoMusicHubApp.swift:96` → `HubSettingsScene` →
`HubSettingsRoot` → `SettingsView`), and a new writer that forgets the call leaves the archive stale until the next
launch. (The review also named the recovery import and the CLI. Neither writes the live scan list: the recovery
import saves into a new isolated suite (`ProjectVaultRecoveryService.swift:296-304`), and the CLI is another process.)

Persistence is snapshot based. The archive keeps the loaded roots and a bookmark per root in memory
(`roots`, `scanRootBookmarks`, `ArchiveBrowserViewModel.swift:51, 445-448`) and after an add or a remove writes the
whole in-memory list back through `persistRoots()` (`+Roots.swift:200-335`). Because the in-memory list leaves out
roots whose access failed, Vault roots and disabled records, the merge needs about 200 lines of rules to keep those
records: `unresolvedPersistedScanRoots` (`:340-362`), Vault roots kept and repaired in place, disabled records kept,
alias-aware matching (`/tmp` and `/private/tmp`, a moved folder whose bookmark resolves elsewhere), and the
same-folder Vault repair `refreshFailedVaultBookmarkForSameCanonicalReauthorization` (`:482-508`).

Each writer has its own follow-up:

| After | Catalog | Scan | Footer warnings | Vault recovery |
| --- | --- | --- | --- | --- |
| `addRoots` | kept | yes | root-access warning updated | no |
| `removeRoot` | cleared | no ("Archive roots changed. Scan to refresh.") | unrelated warning restored | no |
| `applyProjectVaultSettingsChange` | cleared when roots changed | yes | cleared | yes |
| `applyRepairedSettings` | cleared when roots changed | yes | settings warning resolved | snapshots re-read |

Problems:

- **Order and duplication in the composition.** Two contexts, a count that must be kept in step by hand, and an
  `assert` that only fires in debug builds.
- **No locality for scan-list rules.** The write rules live in the archive view model, so Settings, Set Up and the
  composition reach into it, and the Vault pane must remember a follow-up call.
- **Behavior that falls out of the snapshot design** (observed in source, not checked at runtime):
  - A root whose access failed is not in `roots`, so Settings does not list it and nothing can remove it; the board
    can only grant access again.
  - With Vault on, Settings lists the Vault Active root with a Remove button. Remove drops it from `roots`, but
    `persistRoots` keeps every Vault-role record, so it comes back at the next load.
  - A failed save of a root from Settings shows in the archive's footer, not in Settings.
  - After a Remove the board is empty (remaining roots included) until the person presses Scan.

## Design A — the store owns the scan list; the archive follows it (chosen)

1. **One context (step 1).** Delete `registeredToolCount` and the Dev Tool label that shows it. Move
   `persistenceIssues` out of `ToolContext` to its only reader: `AppComposition` keeps the list and passes it to
   `AppShellView`, as it passes `registry`. Then the context is built once, before the archive view model, and
   `finalContext` goes.

2. **One module edits the scan list (step 2).** A new value type in AppCore, next to `VaultRootManager`, holds the
   scan-list rules. It edits stored settings and does no file operation:

   ```swift
   /// The folders the Archive Browser scans, as stored in settings: which stored roots it scans,
   /// and the two edits a person makes. Every other stored root keeps its record: Vault roots,
   /// disabled records and roots whose access failed.
   public struct ArchiveScanList: Sendable {
       public init(bookmarks: any SecurityScopedBookmarkResolving = FoundationSecurityScopedBookmarks())

       /// The scan list, in stored order (today's `filteredEffectiveScanRoots`).
       public static func scannedRoots(in settings: AppSettings) -> [StoredMusicRoot]

       /// Adds `folder`. The same folder (alias or moved bookmark) keeps its record and gets `bookmark`;
       /// the folder of a failed Vault root repairs that root in place. Marks archive onboarding done.
       public func adding(_ folder: URL, bookmark: Data?, to settings: AppSettings) -> AppSettings

       /// Removes `folder` from the scan list. A Vault root is changed in the Project Vault pane, not here.
       public func removing(_ folder: URL, from settings: AppSettings) -> AppSettings
   }
   ```

   Edits replace the snapshot merge: an add or a remove touches only the matching record, so the rules that kept
   everything else (`unresolvedPersistedScanRoots`, the retained-record branches of `persistRoots`) have nothing left
   to do. The archive keeps the read side: resolving bookmarks, holding security-scoped access, the access failure,
   `writeProtectedRoots()`. `scanRootBookmarks` goes; bookmarks live only in the stored roots.

3. **The archive follows the store (step 3).** The archive subscribes to `ToolContext.appSettings` and runs one
   reaction for every writer:

   ```swift
   /// The archive's one answer to a change of stored roots or Vault settings, from any writer.
   /// It reads the store, so a late publish can never roll the archive back.
   func followStoredSettings()
   ```

   When the root inputs differ from the ones last loaded, it does a root reload: it keeps the catalog when folders
   were only added, and otherwise clears the root-bound state (keeping unrelated footer warnings); it scans when the
   scan list is not empty; it runs Vault recovery when a Vault input changed. When the root inputs are the same (a
   Keep Local pin, an automation switch), it only refreshes the Vault presentation. The archive's own add calls the
   reaction at once after its write, so the board and the tests see the result synchronously; the later publish then
   finds nothing new. `applyProjectVaultSettingsChange` goes; `applyRepairedSettings` resolves the settings warning,
   re-reads the Vault snapshots and calls the same reaction.

4. **Settings and Set Up use the store (step 4).** Settings' Music archive list shows
   `ArchiveScanList.scannedRoots(in: session.settings)`. Add and Remove call `ArchiveScanList` inside
   `session.persistSettings`, so a failed save shows in Settings' pinned banner. The Vault pane saves and calls
   nothing. `SettingsView`, `HubSettingsRoot` and `HubSettingsScene` lose `archiveViewModel`. The Set Up sheet reads
   the scan list from `appSettings`; its Choose Folder still asks the archive (`addRoot`), which already lives in the
   main window with the shell. `roots` loses `public`; `removeRoot` and `persistRoots` go.

The archive view model stays built by the composition: the shell (persistent player, Set Up), the repair handler,
the first-launch onboarding and the converter handoff use it. Settings no longer does.

## Design B — a shared `ArchiveRoots` object (not chosen)

The review's sketch: move the loaded roots, the bookmarks, the security-scoped access, the access failure and the
snapshot merge into an `@MainActor` observable object in AppCore, with `add`, `remove`, `retryAccess` and `reload`.
The composition builds it before the archive view model and hands it to the archive, Settings and Set Up. The archive
observes its `roots` and scans; Settings lists `roots` and calls `add` and `remove`.

Why it is not chosen:

- **The follow-up call stays.** A Vault pane save changes the scan list through the store, so Settings must still call
  `reload()`, and the archive still needs a second signal for the Vault presentation and recovery. B moves the
  ordering rule; A removes it.
- **Two copies of the scan list stay.** The object holds an in-memory list beside the stored one, so the 200-line
  snapshot merge moves with it, and so do its gaps (a failed root that nothing lists, a Vault root that Remove only
  hides).
- **A larger interface.** Callers must learn six members and when to call `reload`; tests need the object, a store
  and a resolver. A's module is three functions over a value, tested without a view model.

B's one advantage is lower risk in step 2: the merge code moves unchanged, while A rewrites persistence as edits.
A covers that risk by porting every stored-outcome assertion of the current suites to the new module's tests before
the merge is deleted.

## Comparison

| | A: store owns the scan list | B: shared `ArchiveRoots` object |
| --- | --- | --- |
| Depth | Three functions hide the scan-list rules; one archive reaction hides the root reload | Six members plus a publisher; the merge stays inside |
| Locality | Write rules in one AppCore file; one reaction for every writer | Write rules in one object; Vault changes still need a second path |
| Caller knowledge | Edit settings; nothing to call afterwards | Call `add`, `remove`, and `reload` after a Vault save |
| Enforcement | Compiler: Settings has no archive view model, `removeRoot` and the public `roots` setter are gone; source test for Settings | Compiler for the object; the `reload` rule is judgment |
| Risk | Medium: persistence rewritten as edits; asynchronous follow for other writers | Lower in persistence; same composition change |

**Decision: A.** It deletes the snapshot merge, the follow-up calls and the Settings scene's dependency on the archive,
and it fixes the three gaps listed above. No ADR is needed: the lasting part goes into
[architecture.md](../architecture.md) and closes open question 1 of the map in step 5.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Count registered tools | `AppComposition` by hand, `ToolContext` | none (the label goes) |
| Launch warnings (store and registry failures) | `ToolContext.persistenceIssues`, two contexts | `AppComposition.persistenceIssues`, passed to `AppShellView` |
| Which stored roots the archive scans | `ArchiveBrowserViewModel.filteredEffectiveScanRoots` (private) | `ArchiveScanList.scannedRoots(in:)` |
| Add or remove a folder in stored settings | `ArchiveBrowserViewModel.persistRoots` merge | `ArchiveScanList.adding` / `removing` |
| Resolve, hold access, report access failure | `ArchiveBrowserViewModel` | unchanged |
| React to a stored-root or Vault change | each writer's own follow-up call | `ArchiveBrowserViewModel.followStoredSettings()`, driven by `appSettings` |
| Same-folder Vault root repair | `refreshFailedVaultBookmark…` plus the merge | `ArchiveScanList.adding` |

### Interfaces

- **New:** `ArchiveScanList` (AppCore/Settings); `AppComposition.persistenceIssues`; `AppShellView(…,
  persistenceIssues:)`; `ArchiveBrowserViewModel.followStoredSettings()` (internal).
- **Removed:** `ToolContext.registeredToolCount` and `persistenceIssues` (and their init parameters); `finalContext`;
  the hand count and its `assert`; `ArchiveBrowserViewModel.removeRoot`, `persistRoots`,
  `applyProjectVaultSettingsChange`, `scanRootBookmarks`, `unresolvedPersistedScanRoots`,
  `refreshFailedVaultBookmarkForSameCanonicalReauthorization`, `filteredEffectiveScanRoots`; `archiveViewModel` in
  `SettingsView`, `HubSettingsRoot`, `HubSettingsScene` and `HubSetupView`.
- **Changed:** `roots` is `@Published var` without `public` (tests still seed it); `addRoot`/`addRoots` write through
  `ArchiveScanList` and then follow the store.
- **Unchanged:** the settings JSON, `StoredMusicRoot`, `effectiveScanRoots`, `VaultRootManager`, `retryStoredArchiveAccess`
  (it resolves without writing), `completeArchiveOnboarding`, `writeProtectedRoots`, `ToolContext`'s defaults.

### Dependency direction

No new module or module edge. `ArchiveScanList` sits in AppCore, which FeatureArchiveBrowser and the app already
import. The app target's edge to `ArchiveBrowserViewModel` shrinks to the shell and the composition.

## Behavior and compatibility requirements

1. **Same stored result.** For every case the current suites pin, an add or a remove leaves the same stored roots:
   stable IDs, refreshed bookmarks, Vault roots kept, disabled records kept, other failed roots kept, alias matching
   (`/tmp` and `/private/tmp`, a moved folder by its bookmark), the same-folder Vault repair in place, and a different
   folder never rebinding a Vault root. One known difference: an add or a remove no longer cleans up unrelated
   duplicate records; `effectiveScanRoots` already ignores them when scanning.
2. **Every writer reaches the archive.** A scan-list change from Settings, Set Up or the board, and a Vault pane save
   (Active or Archive folder, Vault on or off), reaches the archive without a call: loaded roots, watcher, access
   strip and scan follow on the next main-queue turn. A Vault input change runs Vault recovery, as a Vault save does
   today. A Keep Local pin or another setting that leaves the root inputs alone causes no root reload and no scan.
3. **Settings lists the stored scan list (behavior change; approved).**
   a. A root whose access failed is listed, and Remove removes it (today it is not listed and cannot be removed).
   b. With Vault on, the Vault Active root is listed without Remove, with the description "Project Vault Active
      Projects" (today Remove hides it only until the next load).
   c. The test fixture root and the development bootstrap root, which are never stored, are not listed (today they
      are, in fixture and development runs only).
4. **Remove rescans (behavior change; approved).** After a folder leaves the scan list, the archive clears the
   root-bound state as today and then scans the remaining folders, showing "Scanning archive...". Today the board stays
   empty with "Archive roots changed. Scan to refresh." until the person presses Scan. An add keeps the catalog and
   scans, as today. A Vault change keeps today's status sentences.
5. **Warnings survive.** An unrelated footer warning survives any root reload (today only a Remove keeps it; a Vault
   save clears it). The root-access warning follows the first failed root, as today.
6. **Errors show where the person acted (behavior change; approved).** A failed root save, or a bookmark that
   could not be made, shows in Settings' pinned banner when the person acted in Settings. Today it shows in the
   archive's footer, which is in another window. From the board and Set Up it shows in the footer, as today.
7. **Onboarding.** Any add marks archive onboarding done, as `addRoots` does today.
8. **Unchanged:** no file operation (edits change settings only); fixture runs and the E2E smoke behave as today;
   unreadable settings refuse every root edit and show the repair notice; scan exclusions take effect at the next
   scan; a writer in another process (the CLI) is still not followed.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(roots step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `ARCH`: `T(FeatureArchiveBrowserTests)` plus every `*SourceTests` in `AppCoreTests`
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline

- The full gates passed on `9db2010` (its commit message: "ci.sh and strict E2E green"). Record that instead of
  re-running, unless code commits landed since.

### Step 1: One tool context

- Delete `ToolContext.registeredToolCount` and its init parameter; delete the hand count, its comment and the
  `assert` in `AppComposition.make()`; delete the Dev Tool's "Registered tools" line.
- Move `persistenceIssues` from `ToolContext` to `AppComposition` (a `let`), and pass it to `AppShellView` from
  `NikoMusicHubApp`. Build the context once; delete `finalContext`. Update the launch comment.
- Drop the argument from the call sites in tests and `script/performance/*.swift`, and the assertion that reads it. Replace
  `ToolContextTests.testContextRetainsPersistenceIssues` with a source test: `AppShellView` reads the issues it is
  given, and `AppComposition.make()` builds exactly one `ToolContext(`.
- Map: the launch flow (step 3 of "Launch") and gap 2 change in this commit (AGENTS.md: a changed main flow updates
  the map in the same commit).
- **Verify:** `B`, then `T(AppCoreTests)`, `ARCH`, and the converter, downloader and stem suites that build contexts.

### Step 2: One module edits the scan list

- Add `Sources/AppCore/Settings/ArchiveScanList.swift` as in Design A. Move `filteredEffectiveScanRoots` there as
  `scannedRoots(in:)`; move the canonical-path helper it needs.
- Add `Tests/AppCoreTests/ArchiveScanListTests.swift` first, from the stored-outcome assertions of
  `ArchiveRootBookmarkPersistTests`, `ArchiveMultiRootRecoveryTests`, `ArchiveActiveRootRecoveryTests` and
  `ArchiveAccessRecoveryTests`: a new folder; the same folder by alias and by moved bookmark (no duplicate, ID kept,
  bookmark refreshed); a failed Vault root repaired in place and its enabled Scan-only duplicate dropped; a different
  folder never rebinds a Vault root; remove keeps Vault roots, disabled records, other failed roots and the Vault
  archive binding; remove of a failed root removes it (requirement 3a); remove of the Vault Active root changes
  nothing; onboarding is marked done; `scannedRoots` leaves out the Vault Archive root while Vault is on.
- `addRoots` and `removeRoot` write through `ArchiveScanList` inside `settingsStore.updateSettings`, then reload as
  each does today (behavior kept in this step). Delete `persistRoots`, `unresolvedPersistedScanRoots`,
  `refreshFailedVaultBookmark…` and `scanRootBookmarks`.
- Archive suites: tests that seed `roots` or `scanRootBookmarks` only to feed the snapshot merge, or call
  `persistRoots()`, seed stored settings instead. Record each changed expectation as a revision.
- **Verify:** `B`, then `T(ArchiveScanListTests)`, `ARCH`.

### Step 3: The archive follows the store

- Add `followStoredSettings()` and the root-inputs value it compares; subscribe to `appSettings.$settings` in the
  view model's init (weak capture). Route `addRoots`, `removeRoot`, `applyRepairedSettings` and today's
  `applyProjectVaultSettingsChange` body through it; delete `applyProjectVaultSettingsChange`. Apply requirements 4
  and 5 here.
- Tests (`Tests/FeatureArchiveBrowserTests/ArchiveStoredRootsFollowTests.swift`, each waiting for the event it needs:
  the scan override being called, or a `roots` publish):
  1. Another writer adds a folder through `ArchiveScanList`: the archive loads it, keeps the catalog and scans.
  2. Another writer removes a folder: the archive clears the root-bound state and scans the rest; an unrelated
     footer warning survives.
  3. Vault switched on with an Active folder: the roots reload and Vault recovery runs (the fake runtime records it).
  4. A Keep Local pin, then a folder add: exactly one scan, for the add (event-ordered, no timeout).
  5. The archive's own add shows the new root synchronously, and the later publish causes no second scan.
- Convert `ProjectVaultPresentationCacheTests:103` and `ProjectVaultScanBoundaryTests:57` (which call
  `applyProjectVaultSettingsChange`) to write the store and wait.
- **Verify:** `B`, then `ARCH`.

### Step 4: Settings and Set Up use the store

- `SettingsView`: the Music archive list from `ArchiveScanList.scannedRoots(in: session.settings)`; Vault Active row
  without Remove (requirement 3b); Add makes the bookmark, then edits inside `session.persistSettings`, which reports
  failures in the banner (requirement 6); Remove the same. `saveProjectVaultSettings` only saves.
- Remove `archiveViewModel` from `SettingsView`, `HubSettingsRoot`, `HubSettingsScene` and `NikoMusicHubApp`'s Settings
  scene. `HubSetupView` takes `appSettings` and reads the scan list. `roots` loses `public`; delete `removeRoot` if
  only tests call it then (tests use `ArchiveScanList` and wait).
- Source tests: `SettingsLiquidSourceTests.testSettingsKeepsSafetyAndAccessibilityHooks` requires the
  `ArchiveScanList` calls instead of `archiveViewModel.addRoot`/`removeRoot`; a new assertion that no Settings source
  file mentions `ArchiveBrowserViewModel`.
- **Verify:** `B`, then `T(ArchiveScanListTests)`, `ARCH`.

### Step 5: Docs, full gates, live check

- `docs/architecture.md`: a short "Archive scan list" section (the store owns it, `ArchiveScanList` edits it, the
  archive follows `appSettings`). `docs/architecture-map.md`: state-owner row for archive roots, gap 1 (Settings no
  longer holds the archive view model), open question 1 closed, "Last verified".
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - A live check with `verify-niko-music-hub`, in an isolated run with a scratch copy of the fixture archive:
    1. Dev Tool shown (`NIKO_MUSIC_HUB_SHOW_DEV_TOOL=1`): it renders without the "Registered tools" line. A run whose
       isolated database path is blocked by a folder shows "Archive database unavailable" in the warning banner.
    2. Settings > Music archive > Add a second scratch folder: the board shows its songs with no relaunch. Remove it:
       the board rescans and shows the first folder's songs.
    3. Board > Add Folder while Settings is open: Settings lists the folder at once. Set Up > Choose Folder: the Set
       Up row names the folder.
    4. Settings > Project Vault: choose Active and Archive scratch folders and switch Vault on: the board follows with
       no relaunch; Settings lists the Active folder without Remove. Pin a song Keep Local: no "Scanning" status.
    5. Quit, move the second scratch folder to the Trash, relaunch: the board shows the access strip; Settings lists
       the folder; Remove clears the strip.

## Completion criteria

- One `ToolContext` per launch; `registeredToolCount` and the hand count are gone; launch warnings reach the shell.
- `ArchiveScanList` is the only code that adds or removes a scan-list folder; its tests run without a view model.
- The Settings scene has no archive view model; no Settings file names `ArchiveBrowserViewModel` (source test).
- Every scan-list or Vault change reaches the archive through `followStoredSettings()`; nothing calls into the
  archive after a save.
- Requirements 1, 2, 5, 7 and 8 hold; 3, 4 and 6 hold as approved. Existing tests pass, edited only where they fed the
  snapshot merge or called the removed functions (each recorded as a revision).
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the owners; open question 1 is closed. This plan is
  deleted.

## Follow-ups (not part of this plan)

- **Vault root edits have two copies.** `ProjectVaultSettingsView.chooseRoot` runs `VaultRootManager.replacingRoot`,
  then repeats its record edit inside `onSave` (`ProjectVaultSettingsView.swift:450-457`). `ArchiveScanList` and
  `VaultRootManager` could become one music-root editor with one `apply` path.
- **`ToolContext` defaults.** `init` still creates a job center, router, settings observer and repair model when a
  caller leaves them out. Two production callers exist and both are correct; making them required would add four
  arguments to 23 test sites for no behavior change. Revisit when a third production caller appears.
- **Grant Access as a reload.** `retryStoredArchiveAccess` resolves the failed root by hand; with the store as owner
  it could be a forced root reload.
- **The root reset** (map gap 6) still resets about 35 properties by hand; this plan does not change it.
