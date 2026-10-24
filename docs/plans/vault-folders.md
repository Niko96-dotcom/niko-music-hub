# Plan: The Vault's folder layout in one module, and one place that builds its engines

**Status:** Approved by Niko on 2026-10-24, including requirement 4. In progress — see [Progress](#progress).  
**Date:** 2026-10-24  
**Source:** finding #12 of the 2026-10-22 architecture review ("Vault on-disk layout in one module"). It also closes
the folder-name half of gap 9 in [architecture-map.md](../architecture-map.md).  
**Scope:** where the Project Vault's folder names are built and checked (`NikoMusicCore/Vault`, the runtime in
`AppCore/ProjectVault`, `ProjectVaultPresentation`, the restore sheet's options, the archive's recovery reveal), and
how the runtime builds its transfer and restore engines; their tests and docs. No change to the on-disk format, the
transfer and restore state machines, the admissions, the manifest or the UI.

This plan keeps two kinds of statement apart. **Current** describes the code at `33bc9af`. **Planned** describes the
target, which does not exist yet. When the plan is done, the lasting part moves to [architecture.md](../architecture.md)
and this file is deleted (see [Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed). Find a step's
commit with `git log --grep='(vault folders step N)'`.

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates passed on `14412e3`; `33bc9af` changed docs only; no re-run |
| 1 One module for the folder names | done | `git log --grep='(vault folders step 1)'` | strict build; `NikoMusicCoreTests` 841 (5 new, 1 skipped), AppCore Vault and `*SourceTests` 278, archive Vault suites 79, 0 failures |
| 2 Every other site uses it | done | `git log --grep='(vault folders step 2)'` | strict build; `NikoMusicCoreTests` 841 (1 skipped), AppCore Vault and `*SourceTests` 280, archive Vault suites 79, 0 failures; a planted `".niko-staging"` in `LocalVaultRestoreEngine.swift` failed `VaultFoldersSourceTests`, then was removed |
| 3 One place builds the engines | done | `git log --grep='(vault folders step 3)'` | strict build; `NikoMusicCoreTests` 841 (1 skipped), AppCore Vault and `*SourceTests` 282, archive Vault suites 79, 0 failures; with the clock left out of the factory both new clock tests failed |
| 4 The restore engine refuses every reserved Active folder | done | `git log --grep='(vault folders step 4)'` | strict build; `NikoMusicCoreTests` 843 (2 new, 1 skipped), AppCore Vault and `*SourceTests` 282, archive Vault suites 79, 0 failures; with the old staging-only rule, the engine restored into `.niko-recovery/Song` and the new test failed |
| 5 Docs, full gates, live check | not started | | |

## Revisions

Record every deviation from the steps below here, numbered, with its reason.

1. **Step 1: one restore staging URL gains a trailing slash.** The linked-restore entry point
   (`LocalVaultRestoreEngine.swift:235`) built its staging URL without `isDirectory: true`; it now uses
   `VaultFolders.staging(in:projectID:operationID:)` like the other entry point. The folder on disk is the same; a new
   record's `stagingURL` string ends in `/`, and every check compares paths, not URL strings. Old records still load.
2. **Step 3: default admissions instead of optionals.** The fail-closed defaults became named statics on the engine
   (`LocalVaultTransferEngine.refusesWrites`, `refusesRemovals`), used by the engine's initializer and as the factory's
   defaults. A call that leaves an admission out gets the same refusal as before.
3. **Step 3: the factory sits in `LiveProjectVaultRuntime.swift`,** beside `configuration()`, not in a new extension
   file: it is the runtime's construction rule, not a separate responsibility.
4. **Step 4: one helper for both checks.** `VaultFolders.isInReservedActiveFolder(_:activeRoot:)` judges the resolved
   path below the root; the restore engine's `destinationURL` and the runtime's `safeContainedRestoreDestination` both
   call it, so a symlink into an app folder is refused too.

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Archive root, Active root | The two Project Vault folders the person chooses | `configuration.archive.url`, `configuration.active.url` |
| Generation | One verified copy of a project in the Archive root | `generations/<project>/generation-<transfer>` |
| Staging | A copy in progress: an archive in the Archive root, a restore in the Active root | `.niko-staging/<project>/<transfer or restore>` |
| Recovery folder | Where launch recovery sets aside a surviving Active copy | `.niko-recovery/<transfer>/<attempt>/<folder>` in the Active root |
| Reserved folder | A folder the app owns inside a root; never a song, never a restore target | `generations`, `.niko-staging`, `.niko-recovery` |
| Folder layout | The names and nesting above. They are an on-disk format: Vaults made by earlier versions must stay readable | none; spelled out per site |

`VaultArchiveLayout` (the per-file name escaping inside a generation, `portableNamesV1`) is a different thing and does
not change.

## Current architecture (observed at `33bc9af`)

### The folder names are spelled out on 28 lines

| File | Lines | What it builds or checks |
| --- | --- | --- |
| `NikoMusicCore/Vault/LocalVaultTransferEngine.swift` | 195-202 | archive staging and generation URLs for a new transfer |
| | 487-489 | the expected generation before a removal resumes |
| | 505 | the recovery folder for a surviving Active copy |
| | 943 | archive staging containment before a staging folder is removed |
| | 1106-1107 | staging and generations roots in `validatePaths` |
| | 1389-1392, 1408 | the expected generation in `hasPersistedGenerationPath` |
| `NikoMusicCore/Vault/LocalVaultRestoreEngine.swift` | 191, 235 | restore staging URLs (two restore entry points) |
| | 684 | the staging root in `validate` |
| | 722 | the generations root in `validateArchiveGeneration` |
| | 747 | staging excluded from restore destinations |
| `NikoMusicCore/Vault/ProjectArchiveLocation.swift` | 25 | `generations` and `.niko-staging` are not ordinary archive folders |
| `AppCore/ProjectVault/LiveProjectVaultRuntime+Archive.swift` | 44-46 | the expected generation when matching a song to its transfers |
| `AppCore/ProjectVault/LiveProjectVaultRuntime+Restore.swift` | 168 | staging excluded from the pinned restore destination |
| `AppCore/ProjectVault/ProjectVaultPresentation.swift` | 80, 117-120 | the generations root and the bound generation for cards |
| `AppCore/ProjectVault/ProjectVaultRestoreOptions.swift` | 30, 70 | the restore sheet refuses any `.niko-` path component |
| `AppCore/ProjectVault/ProjectVaultRestoreDrill.swift` | 37 | the drill's synthetic staging folder |
| `FeatureArchiveBrowser/ArchiveBrowserViewModel+ProjectVaultRecovery.swift` | 36 | the recovery folder for "Reveal Preserved Files" |

The generation folder name `generation-<lowercased transfer UUID>` is built in five places; a site that formats the UUID
differently would not find a verified copy. The incremental scanner skips every hidden root folder
(`ArchiveSongFolderResolver.swift:48-52`), which covers the `.niko-` folders without naming them.

### Three rules for "reserved"

| Where | Reserved |
| --- | --- |
| `ProjectArchiveLocation.isOrdinaryArchivePath` (Archive root) | `generations`, `.niko-staging` (case-insensitive, top level) |
| `ProjectVaultRestoreOptions` (restore sheet) | any path component starting with `.niko-` |
| `LocalVaultRestoreEngine.destinationURL`, `safeContainedRestoreDestination` (Active root) | `.niko-staging` only |

So the restore engine accepts a destination inside `.niko-recovery`, which the sheet refuses. The UI never sends one
today; the engine is the last check and is weaker than the sheet.

### Ten engine constructions, two of them without the runtime's clock

The runtime builds `LocalVaultTransferEngine` five times (`+Archive.swift:306, 447`, `+Recovery.swift:25, 77, 150`)
and `LocalVaultRestoreEngine` five times (`+Recovery.swift:42, 159`, `+Restore.swift:41, 83, 367`), each with its own
argument list. `+Recovery.swift:25` passes neither `now` nor `recoveryPolicy`, and no restore construction passes
`now`, so an injected clock (`LiveProjectVaultRuntime(now:)`) does not reach those paths. In production both are the
defaults, so nothing differs today; in tests the times in those records come from the wall clock.

Problems:

- **No locality for an on-disk format.** Adding a reserved folder means editing engines, the archive-location parser,
  the presentation and the sheet; missing one can show phantom song cards or let a restore land in an app folder.
- **Uneven safety checks.** The engine's reserved-folder rule is weaker than the UI's.
- **Engine construction is copied ten times,** and two copies already dropped the clock.

## Design A — `VaultFolders` plus one engine factory (chosen)

1. **One module for the names (steps 1 and 2).** A stateless enum in `NikoMusicCore/Vault/` that builds every app
   folder from a root and says which names are reserved:

   ```swift
   /// The folders the app keeps inside the two Project Vault roots. They are an on-disk
   /// format: Vaults made by earlier versions must stay readable, so the names never change.
   ///
   ///   Archive root  generations/<project>/generation-<transfer>   verified copies
   ///                 .niko-staging/<project>/<transfer>             an archive in progress
   ///   Active root   .niko-staging/<project>/<restore>              a restore in progress
   ///                 .niko-recovery/<transfer>/<attempt>/<folder>   copies set aside by recovery
   public enum VaultFolders {
       public static func staging(in root: URL) -> URL
       public static func staging(in root: URL, projectID: ProjectID, operationID: UUID) -> URL
       public static func generations(in archiveRoot: URL) -> URL
       public static func generation(in archiveRoot: URL, projectID: ProjectID, transferID: UUID) -> URL
       public static func generationFolderName(transferID: UUID) -> String
       public static func recovery(in activeRoot: URL, transferID: UUID) -> URL
       public static func preservedActiveCopy(in activeRoot: URL, transferID: UUID, folderName: String) -> URL
       /// `generations` and `.niko-staging`, case-insensitive: never an ordinary archive folder.
       public static func isReservedInArchiveRoot(_ name: String) -> Bool
       /// Any `.niko-` name: never a restore destination.
       public static func isReservedInActiveRoot(_ component: String) -> Bool
   }
   ```

   Every site in the table calls it. Each site keeps its own comparison (symlink resolution, URL authority,
   component checks): only the expected URL and the names move. A source test keeps the literal names in
   `VaultFolders.swift`.

2. **One engine factory (step 3).** Two runtime methods build every engine with the same roots, stores, catalog,
   opener, clock and recovery policy; only the provider and the admissions vary per call:

   ```swift
   func makeTransferEngine(_ configuration: Configuration, provider: any ArchiveStorageProvider,
                           writeAdmission: WriteAdmission? = nil, removalAdmission: RemovalAdmission? = nil) throws
       -> LocalVaultTransferEngine
   func makeRestoreEngine(_ configuration: Configuration, provider: any ArchiveStorageProvider,
                          writeAdmission: WriteAdmission, linkedArchiveValidation: LinkedArchiveValidation)
       -> LocalVaultRestoreEngine
   ```

   A `nil` admission keeps the engine's fail-closed default, so each call keeps exactly the admissions it has today.

3. **One reserved rule in the engine (step 4).** The restore engine and the runtime's pinned restore destination refuse
   any destination inside a reserved Active folder (`VaultFolders.isReservedInActiveRoot`), as the sheet does.

## Design B — a layout object that also owns the path checks (not chosen)

Make `VaultFolders` deeper: besides the names, it owns every "is this URL a safe Vault path" check that the engines,
the runtime and the presentation each implement today (`validatePaths`, `hasPersistedGenerationPath`,
`isBoundGenerationPath`, `matchesCurrentSource`, the staging containment checks), with one comparison semantics.

Why it is not chosen now:

- **The checks differ on purpose, and in safety code.** `hasPersistedGenerationPath` compares URL authority and path
  components without resolving symlinks; `matchesCurrentSource` resolves them; `validatePaths` uses
  `PathSafety.isResolvedContainedWithoutNestedSymlinks`. One semantics means changing at least two of them in the
  transfer and removal paths, which needs the fault-injection plan that finding #13 asks for.
- **A is a strict subset.** Every check B would own reads its expected URL from `VaultFolders` after A, so B stays a
  later step without rework.

B's advantage is depth: one owner for "is this a Vault path", not only for the names.

## Comparison

| | A: names + factory | B: names + path checks |
| --- | --- | --- |
| Depth | Small: the layout and the reserved rules in one place; the factory hides ten argument lists | More: one owner for Vault path safety |
| Locality | The on-disk format in one file; engine construction in two methods | The same, plus path safety |
| Behavior | Unchanged except requirement 4 (and the clock in tests) | Changes comparison semantics in safety code |
| Enforcement | Source test for the literal names; compiler for the factory | The same |
| Risk | Low: same URLs, same checks | Medium-high: needs fault-injection tests |

**Decision: A.** It removes the 28 spellings, makes the reserved rule one rule, gives every engine the runtime's clock,
and keeps every safety comparison as it is. No ADR is needed: the lasting part goes into
[architecture.md](../architecture.md) in step 5.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Name and nest the app's folders in a Vault root | 9 files, 28 lines | `VaultFolders` (NikoMusicCore) |
| Say which names are reserved | three rules in three places | `VaultFolders.isReservedInArchiveRoot`, `isReservedInActiveRoot` |
| Check that a URL is a safe staging, generation or destination path | each engine, the runtime, the presentation | unchanged (each site), with URLs from `VaultFolders` |
| Build transfer and restore engines | ten constructions in the runtime | `makeTransferEngine`, `makeRestoreEngine` |

### Interfaces

- **New:** `VaultFolders` (NikoMusicCore); `LiveProjectVaultRuntime.makeTransferEngine`, `makeRestoreEngine`
  (internal).
- **Changed:** `LocalVaultRestoreEngine` destinations and `safeContainedRestoreDestination` refuse every reserved
  Active folder (requirement 4).
- **Unchanged:** both engine initializers, `VaultTransferRecord`, `VaultRestoreRecord`, the manifest,
  `VaultArchiveLayout`, the admissions, the state machine, every UI string.

### Dependency direction

No new module or module edge. `VaultFolders` sits in `NikoMusicCore/Vault/`; AppCore and FeatureArchiveBrowser already
import NikoMusicCore.

## Behavior and compatibility requirements

1. **Same on-disk format.** Every folder keeps its name, nesting and UUID formatting (lowercased); `ProjectID` keeps its
   `description` form. A golden test pins the exact relative paths, and the existing archive, restore, recovery and
   durability suites pass unchanged.
2. **Same checks.** Every staging, generation and destination check compares the same URLs in the same way as today;
   only where the expected URL comes from changes.
3. **Same admissions.** Each engine gets exactly the write and removal admissions it gets today; a missing one keeps the
   engine's fail-closed default.
4. **One reserved rule for restore destinations (behavior change; approved).** The restore engine and the
   runtime's pinned restore destination refuse a destination inside any `.niko-` folder of the Active root, as the
   restore sheet already does. Today they refuse only `.niko-staging`. The UI never sends such a destination, so a
   person sees no change; a caller that bypasses the sheet gets `invalidDestination`.
5. **The runtime's clock everywhere.** Every engine the runtime builds gets its `now` and `recoveryPolicy`. Production
   uses the defaults, so production behavior is unchanged; tests with an injected clock see it in recovery and restore
   records too.
6. **Unchanged:** the scanner (it skips hidden root folders), the archive-location parser's rule for ordinary archive
   folders (`generations`, `.niko-staging`, case-insensitive), the restore drill's behavior, every UI text.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with one commit per
step, tagged `(vault folders step N)` in the subject.

**Verification commands used below:**

- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- `VAULT`: `T(NikoMusicCoreTests)` plus `T(LiveProjectVaultRuntimeTests|ProjectVault)` in AppCore and
  `T(ArchiveVaultObservationTests|ProjectVault)` in FeatureArchiveBrowser
- Full gates: `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app

### Step 0: Baseline

- The full gates passed on `14412e3`; `33bc9af` changed docs only. Record that instead of re-running, unless code
  commits landed since.

### Step 1: One module for the folder names

- Add `Sources/NikoMusicCore/Vault/VaultFolders.swift` as in Design A.
- Add `Tests/NikoMusicCoreTests/VaultFoldersTests.swift` first: a golden test of every relative path (the five shapes
  in the doc comment, with a fixed project and UUIDs, lowercased); the reserved rules (`generations` and `.niko-staging`
  case-insensitive in the Archive root, any `.niko-` component in the Active root, ordinary names not reserved).
- Switch the NikoMusicCore sites: `LocalVaultTransferEngine`, `LocalVaultRestoreEngine`, `ProjectArchiveLocation`.
  Behavior stays the same in this step (the restore engine still refuses only staging).
- **Verify:** `B`, then `VAULT`.

### Step 2: Every other site uses it

- Switch the AppCore and FeatureArchiveBrowser sites: the runtime's expected generation and pinned destination
  (staging only, as today), `ProjectVaultPresentation`, `ProjectVaultRestoreOptions` (`isReservedInActiveRoot`),
  `ProjectVaultRestoreDrill`, `ArchiveBrowserViewModel+ProjectVaultRecovery`.
- A source test (`Tests/AppCoreTests/VaultFoldersSourceTests.swift`): the literals `".niko-staging"`,
  `".niko-recovery"`, `"generations"` and `"generation-` appear in `Sources/` only in `VaultFolders.swift`. Plant one in
  an engine, see it fail, remove it.
- **Verify:** `B`, then `VAULT` and every AppCore `*SourceTests`.

### Step 3: One place builds the engines

- Add `makeTransferEngine` and `makeRestoreEngine` to the runtime (a `+Engines.swift` extension beside the others, or
  the main runtime file). Replace the ten constructions; each call passes the provider and the admissions it passes
  today.
- Tests (`LiveProjectVaultRuntimeTests`, with an injected fixed clock): `recoverInterruptedArchive` (the path that
  `+Recovery.swift:25` builds its engine for) and an ordinary restore both record the injected time. Both fail before
  this step.
- **Verify:** `B`, then `VAULT`.

### Step 4: The restore engine refuses every reserved Active folder

- `LocalVaultRestoreEngine.destinationURL` and the runtime's `safeContainedRestoreDestination` refuse a destination
  inside any reserved Active folder (requirement 4).
- Tests: a restore to `.niko-recovery/Song` is refused with `invalidDestination` (fails before); a restore to an
  ordinary folder still succeeds; the existing staging refusal still holds.
- **Verify:** `B`, then `VAULT`.

### Step 5: Docs, full gates, live check

- `docs/architecture.md`: a short "Vault folders" paragraph in the Project Vault part (the layout, `VaultFolders`, the
  reserved rules, the engine factory). `docs/architecture-map.md`: gap 9 without the folder-name sentence.
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check of the changed docs.
  - A live check with `verify-niko-music-hub` (archive profile, scratch Vault folder, `features/project-vault.md`):
    1. Set up Vault, then Manage storage → Create Backup Copy on a fixture song: the copy lands at
       `vault/generations/<project>/generation-<transfer>` (lowercased) and is verified; `vault/.niko-staging` is
       empty afterwards.
    2. Move that song's scratch Active folder to the Trash, Show archived songs, Restore & Open: the restore verifies
       and `active/.niko-staging` is empty afterwards; `daws` unchanged (dry run).
    3. The restore sheet refuses a destination such as `.niko-recovery/Song` with its existing sentence.

## Completion criteria

- The Vault folder names are built only in `VaultFolders`; the source test enforces it.
- One reserved rule per root; the restore engine is as strict as the sheet (requirement 4, as approved).
- The runtime builds engines only through its two factory methods; every engine gets the runtime's clock and policy.
- Requirements 1 to 3, 5 and 6 hold; existing tests pass unchanged except where a revision records why.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the layout. This plan is deleted.

## Follow-ups (not part of this plan)

- **One owner for Vault path safety (Design B).** After finding #13's fault-injection plan, the path checks could move
  behind `VaultFolders` with one comparison semantics.
- **Finding #13.** Every Vault state change through the state machine; high risk, needs that fault-injection plan.
