# Plan: Keep Local pins behind one module

**Status:** In progress — see [Progress](#progress)  
**Date:** 2026-10-22  
**Source:** finding 3 of the architecture review of 2026-10-22 (now the highest-ranked finding with high confidence)  
**Scope:** `Sources/AppCore` (settings, Project Vault runtime), `Sources/FeatureArchiveBrowser`, one count in `Sources/NikoMusicHub`. No change to the settings format, the UI copy or the Vault engines.  
**Decision record:** [ADR 021](../decisions/021-keep-local-pin-format.md) (accepted by the owner on 2026-10-22)

This plan keeps two kinds of statement apart. **Current** describes the code at `7e0b02b`. **Planned**
describes the target, which does not exist yet. When the plan is done, the lasting part moves to
[architecture.md](../architecture.md) and ADR 021, and this file is deleted (see
[Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed).

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | full gates green on `d458aeb`; `7e0b02b` deleted a plan file only, so no re-run |
| 1 `KeepLocalPins` and its tests | done | `git log --grep='(Keep Local step 1)'` | strict build; `KeepLocalPinsTests` 9/9 (2,000 generated cases for "never match less") |
| 2 Runtime reads | not started | | |
| 3 Runtime writes | not started | | |
| 4 Browser reads | not started | | |
| 5 Browser writes | not started | | |
| 6 Close the raw set | not started | | |
| 7 Docs, ADR, full gates, live check | not started | | |

## Revisions

1. **Step 1: no unit test for "no filesystem call".** The early returns in `contains` (IDs first, then
   no folder work when the stored set has no path keys) are not observable from a unit test without an
   injected canonicalizer, which would be a seam with one adapter. The rule is kept by the code
   structure and its doc comment instead. The canonical-rule equality test lives in `KeepLocalPinsTests`
   (`AppCoreTests` imports `FeatureArchiveBrowser` with `@testable`).

## Terms

| Term | Meaning | Name in code today |
| --- | --- | --- |
| Keep Local | The person's choice to keep a project in Active Projects. The Project Vault never removes a pinned project's Active folder, and the automatic Done copy skips it. UI: "Keep on this Mac", "Review Keep Local". | "Keep Local", "pin" |
| Pin | One project marked Keep Local | — (no type) |
| Pin key | One stored string. A pin is several keys: IDs plus folder paths in several spellings. | elements of `keepLocalProjectIDs` |
| Project ID | A catalog `ProjectID`, stored as its `description` | `record.id.description`, `projectID.description` |
| Song ID | `Song.id`: the standardized folder path, or `loose-project:<root>#<key>` for a loose project file at an archive root (`RootLevelSongIdentity`) | `song.id` |
| Canonical folder path | One spelling per folder: standardized, symlinks resolved, `/private/var` and `/private/tmp` shortened | `ArchiveVaultObservation.vaultCanonicalPath` |

`keepLocalProjectIDs` is a misnomer: it holds song IDs and paths too. The plan does not rename the
stored key (see ADR 021).

## Current architecture (observed at `7e0b02b`)

Pins are stored once, in settings: `VaultSettings.keepLocalProjectIDs: Set<String>`
(`Sources/AppCore/Settings/AppSettings.swift:116`). `ProjectRecord.pinned` is not stored. The runtime
derives it from that set on each snapshot read.

Ten places build their own key set and compare it with the stored set. Each place picks different
members:

| # | Where | Purpose | IDs | Folder spellings |
| --- | --- | --- | --- | --- |
| 1 | `ArchiveVaultObservation.keepLocalKeys(for:)` (`ArchiveVaultObservation.swift:410`) | pin and unpin from the browser | song ID, snapshot project ID, catalog project IDs whose Active location is the song | song folder and transfer source: raw, standardized, resolved, canonical |
| 2 | `ArchiveVaultObservation.isKeepLocalPinned` (`:390`) | card pin flag | project ID, song ID | transfer source: raw, standardized, resolved |
| 3 | `isIntentionalKeepLocalSkip` and `snapshotsContainKeepLocalMatch` (`:442`, `:466`) | skip the automatic Done copy | song ID, project ID | song folder: raw, standardized, resolved, canonical; catalog locations: canonical |
| 4 | card for a song without a snapshot (`:695`) | card pin flag | song ID only | none |
| 5 | `setProjectKeepLocal` unpin (`ArchiveBrowserViewModel+ProjectVault.swift:151`) | remove a pin | keys of #1 | any stored path with the same canonical path |
| 6 | `captureArchiveAuthorization` (`LiveProjectVaultRuntime+Archive.swift:136`) | refuse a capture | song ID, catalog project ID | song folder: authorization canonical, standardized, resolved |
| 7 | `validateAutomaticArchivingEligibility` (`+Archive.swift:403`) | refuse a Done archive | song ID | song folder: standardized, resolved |
| 8 | removal admission (`LiveProjectVaultRuntime+Admission.swift:372`) | refuse removal of the Active copy | two song IDs, project ID | record source: standardized, resolved, authorization canonical |
| 9 | `keepLocalKeys(projectID:destinationURL:)` and the ID-only pre-persist (`LiveProjectVaultRuntime+Restore.swift:139`, `:194`, `:207`) | pin after a restore | project ID | destination: raw, standardized, resolved |
| 10 | `isKeepLocal(record:…)` (`LiveProjectVaultRuntime+Snapshots.swift:123`) | runtime pin flag | project ID | transfer source and Active locations: raw, standardized, resolved |

Two canonical rules exist. `ProjectVaultArchiveAuthorization.canonicalPath` (AppCore) standardizes
and resolves symlinks. `ArchiveVaultObservation.vaultCanonicalPath` (archive feature) also shortens
`/private` aliases for paths that do not exist.

**Bug history.** Two fixes on 2026-10-16 came from keys that did not match:
- L106 (`767bbff`): turning Keep Local off removed one key, but pins were stored under several.
- L048 (`cda1936`): restore pins used keys that the Keep Local toggle never removed.

**User-visible effect.** The Review Keep Local sheet says "N projects are currently pinned", but N
is `keepLocalProjectIDs.count`, the number of keys
(`Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift:190, 575`). One pin writes several
keys.

## Design A — `KeepLocalPins` value type over the same storage (chosen)

One module owns what a pin is, how it matches, and how it is written and removed. The stored set
stays as it is.

```swift
/// Keep Local pins: projects the person keeps on this Mac. The Project Vault
/// never removes a pinned project's Active folder.
///
/// The stored keys mix catalog project IDs, song IDs and folder paths in
/// several spellings, because older builds wrote and compared spellings.
/// Callers describe a project with what they know; matching stays here.
public struct KeepLocalPins: Equatable, Sendable {
    /// One project as a caller knows it. IDs match exactly; folders match by
    /// canonical folder path, so another spelling of the same folder counts.
    public struct Project: Equatable, Sendable {
        public init(projectIDs: [ProjectID] = [], songIDs: [String] = [], folders: [URL] = [])
    }

    public init(storedKeys: Set<String>)
    /// What settings store. Pins written here include every spelling older builds compare.
    public private(set) var storedKeys: Set<String>

    public func contains(_ project: Project) -> Bool
    /// Writes the IDs and, per folder, the raw, standardized, resolved and canonical spellings.
    public mutating func pin(_ project: Project)
    /// Removes the IDs and every stored path with the same canonical folder path.
    public mutating func unpin(_ project: Project)

    /// The folder identity Keep Local and the archive browser compare.
    public static func canonicalFolderPath(_ url: URL) -> String
}

extension VaultSettings {
    public var keepLocalPins: KeepLocalPins { get set }   // over keepLocalProjectIDs
}
```

What the implementation hides:
- **Which strings are paths.** A key that starts with `/` is a path. Everything else is compared
  exactly.
- **The canonical rule.** It is the same as today's `vaultCanonicalPath`.
- **Stored paths are canonicalized once per value.** The value computes the canonical forms of its
  stored path keys at `init`, so each check canonicalizes only the caller's folders.
- **No pin means no filesystem calls.** `contains` with IDs only, or with an empty pin set, touches
  no filesystem.

## Design B — typed pin records with a migration (considered, not chosen)

Store `[KeepLocalPin]`, where each pin holds an optional project ID, song ID and canonical folder
path, under a new settings key. Migrate the old set on first read, and match by fields.

What it would add:
- An honest representation.
- An exact project count for new pins.
- No spelling sets in storage.

Why it is not chosen:
- **Downgrade safety.** An older build reads only `keepLocalProjectIDs`. After a downgrade, or an
  import of a newer recovery bundle into an older build, it would see no pins. The Vault could then
  remove an Active folder the person pinned. Writing both keys avoids that, but then two stores must
  stay in step: a new class of bug in the safety path.
- **Old keys cannot be grouped.** The loose keys of one old pin cannot be linked to each other, so
  the migration cannot produce one record per project. The project count stays wrong for migrated
  pins.
- **The migration would freeze the current filesystem state.** It would canonicalize paths at
  migration time, while today paths are compared at check time.
- **Wider change.** It touches `SettingsRepair` salvage, recovery-bundle round trips and about 90
  test seeds.

A third, smaller option was also rejected: one shared `keepLocalKeys(...) -> Set<String>` builder. It
removes the spelling lists, but callers keep doing set operations, and unpin keeps its own canonical
filter. So the L048/L106 bug class stays. It is a shallow module.

## Comparison

| | A: one module, same storage | B: typed records and migration |
| --- | --- | --- |
| Depth | Three operations (`contains`, `pin`, `unpin`) hide IDs versus paths, spellings, the canonical rule and downgrade-safe writing | Similar interface; more hidden (migration), but two stores during transition |
| Locality | The next pin bug is fixed in one file | Same, plus a migration to keep correct |
| Caller knowledge | Which facts they know about the project (IDs, folders); no spellings, no set algebra | Same |
| Behavior change | Matching is at least as strict as today (see requirements) | Format change; visible after a downgrade |
| Seam | None. A pure value type with one implementation needs no protocol | None |
| Test surface | `KeepLocalPinsTests` on the value type, with temporary folders, symlinks and `/private` paths | Same, plus migration and downgrade tests |

**Decision: A.** It removes the scattered matching knowledge, which was the cause of both recorded
bugs. It does not change data that older builds and recovery bundles read.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| What counts as the same project for Keep Local | 10 hand-built key sets | `KeepLocalPins.contains` |
| Which spellings a pin writes | #1 and #9, each its own list | `KeepLocalPins.pin` |
| What unpin removes | `setProjectKeepLocal` canonical filter | `KeepLocalPins.unpin` |
| Canonical folder rule for Keep Local | `vaultCanonicalPath` (browser), partly the authorization rule (runtime) | `KeepLocalPins.canonicalFolderPath`; `vaultCanonicalPath` forwards to it |
| Which facts describe a song's project in the browser (song ID, snapshot ID, catalog IDs, folders) | `keepLocalKeys(for:)` | `ArchiveVaultObservation.keepLocalProject(for:)` (unchanged facts, returns `KeepLocalPins.Project`) |
| Which facts the runtime has at each gate | each gate | each gate (unchanged facts) |
| The runtime pin flag (`ProjectRecord.pinned`) | `+Snapshots.isKeepLocal` | unchanged, computed with `KeepLocalPins` |
| The authorization canonical path (token binding) | `ProjectVaultArchiveAuthorization.canonicalPath` | unchanged: it binds tokens and is not a Keep Local rule |
| Review obligation (`keepLocalReviewRequired`) | settings and admission | unchanged |

### Public interfaces

- **New:** `KeepLocalPins` and `KeepLocalPins.Project` in `Sources/AppCore/Settings/KeepLocalPins.swift`.
- **New:** `VaultSettings.keepLocalPins` (get and set over the stored set).
- **Changed in step 6:** `VaultSettings.keepLocalProjectIDs` becomes `internal` to AppCore.
  - The settings format, the `CodingKeys` name and the public memberwise `init` parameter stay.
  - Only `AppSettings.swift`, `SettingsRepair.swift` and `KeepLocalPins.swift` use it in Sources.
- **Renamed in the archive feature:** `ArchiveVaultObservation.keepLocalKeys(for:) -> Set<String>`
  becomes `keepLocalProject(for:) -> KeepLocalPins.Project`.
- **Changed in the archive feature:** `ProjectVaultPresentationContext.keepLocalProjectIDs` becomes
  `keepLocalPins: KeepLocalPins`, built once per context refresh.

### Dependency direction

```text
FeatureArchiveBrowser ──► AppCore.KeepLocalPins ◄── AppCore ProjectVault runtime
NikoMusicHub (Settings sheet count) ──► AppCore.KeepLocalPins
KeepLocalPins ──► Foundation, NikoMusicCore.ProjectID
```

No new module edge. `KeepLocalPins` knows nothing about songs, snapshots or the runtime. Callers turn
what they know into a `Project`.

## Behavior and compatibility requirements

1. **Never match less.** For every stored set and every project that any of today's ten checks
   reports as pinned, `contains` reports pinned. The proof: `canonicalFolderPath` gives the same
   result for every spelling that today's checks compare (raw, standardized, resolved, canonical).
   So any exact match today is a canonical match after. A test replays today's checks as reference
   functions against generated stored sets.
2. **Intended difference: match more, in the safe direction.** A pin saved under another spelling
   of the same folder now counts at every gate. It blocks capture, removal and the automatic Done
   copy, and shows as pinned. This is the L048 bug class, fixed. Nothing becomes less protected.
3. **Downgrade-safe writes.** `pin` writes a superset of the keys today's writers (#1, #9) write:
   the IDs plus raw, standardized, resolved and canonical spellings per folder. An older build still
   finds its spellings.
4. **Unpin, no more and no less.** `unpin` removes everything today's toggle removes (the L106 and
   L048 scenarios) and never a key of another project. Another project's keys are other IDs, or
   paths with another canonical path.
5. **Storage unchanged.** The settings key, JSON shape, `SettingsRepair` salvage, recovery-bundle
   export and import, and the diagnostics field `keep_local_projects` (still a key count) stay
   byte-for-byte compatible.
6. **No new filesystem work on per-song paths.** The card for a song without a snapshot (#4) keeps
   an ID-only check. `KeepLocalPins` values are built once per context refresh or snapshot read, not
   per song.
7. **Each gate keeps the facts it has today.** For example, Done eligibility (#7) still does not
   know the catalog project ID. Adding facts would be a behavior change and is out of scope.
8. **Known issue, not changed here.** The Review Keep Local sheet counts stored keys, not projects,
   and old keys cannot be grouped per project. Choosing new wording is a product decision; listed
   under follow-ups.
9. **Out of scope:**
   - unifying the authorization canonical rule
   - the unwired background archiving (review finding 8)
   - `VaultAutomationCandidate.isKeepLocal`

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order, with
one commit per step.

**Verification commands used below:**
- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --skip-build --filter '<suites>'`
- Full gates: run `./script/ci.sh` and `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from
  Terminal.app. The agent shell runs at utility QoS, so recorder probe tests are unreliable there,
  and it has no Accessibility.

### Step 0: Baseline

- The full gates were green on `d458aeb` (2026-10-22). `7e0b02b` only deleted a plan file. Record
  that instead of re-running, unless more commits landed.

### Step 1: Add `KeepLocalPins` and its tests (not wired)

- Add `Sources/AppCore/Settings/KeepLocalPins.swift` and `VaultSettings.keepLocalPins`.
- Add `Tests/AppCoreTests/KeepLocalPinsTests.swift`. It covers:
  - **IDs:** exact match for project and song IDs, including `loose-project:` IDs.
  - **Folders:** match through a symlinked folder, both `/private/var` spellings, and a path that
    does not exist.
  - **Reference checks:** today's ten checks copied into the test as reference functions. Over
    generated stored sets, every old match is a new match.
  - **Pin:** writes are a superset of what #1 and #9 write.
  - **Unpin:** the L106 scenario (project-ID pin on a catalog-only snapshot) and the L048 scenario
    (restore pin under a symlink alias) leave no key behind; another project's keys stay.
  - **No filesystem work for empty pins or ID-only checks:** a set with no path keys answers without
    canonicalizing.
  - **One canonical rule:** `canonicalFolderPath` equals `ArchiveVaultObservation.vaultCanonicalPath`
    for the same inputs. `AppCoreTests` already depends on `FeatureArchiveBrowser`.
- **Verify:** `B`, then `T(KeepLocalPinsTests)`.

### Step 2: Runtime reads use `KeepLocalPins`

- #10 `+Snapshots.isKeepLocal`: build one `KeepLocalPins` per `snapshots()` call.
- #6 capture, #7 Done eligibility and #8 removal admission use `contains`, each with today's facts.
- **Verify:** `B`, then `T(LiveProjectVaultRuntimeTests|LiveProjectVaultReuseCancelTests|KeepLocalReviewRequiredTests|ProjectVaultRestoreKeepLocalTests|KeepLocalPinsTests)`.

### Step 3: Runtime writes use `KeepLocalPins`

- #9: `persistRestoredKeepLocal`, its throwing variant and both `prePersistRestoreProtection`
  overloads call `pin`. The ID-only branch pins a `Project` with the project ID only.
- **Verify:** `B`, then `T(ProjectVaultRestoreKeepLocalTests|LiveProjectVaultRuntimeTests|ProjectVaultRecoveryLifecycleTests|KeepLocalPinsTests)`.

### Step 4: Browser reads use `KeepLocalPins`

- `ProjectVaultPresentationContext` holds `keepLocalPins`.
- #2 and #3 use `contains`. #4 uses `contains(.init(songIDs: [song.id]))`, which stays ID-only.
- `keepLocalKeys(for:)` becomes `keepLocalProject(for:)` with the same facts.
- **Verify:**
  - `B`.
  - `T(ArchiveVaultObservationTests|ProjectVaultPresentationCacheTests|ProjectVaultQueueLivePhaseTests|ProjectVaultRestoreBoardTests|ProjectVaultFriendsWorkflowTests)`.
  - Then all of `FeatureArchiveBrowserTests`.

### Step 5: Browser writes use `KeepLocalPins`

- #5 `setProjectKeepLocal` calls `pin` and `unpin`, and its own canonical filter is deleted.
- `confirmWorkflowDoneKeepLocal` calls `pin`.
- **Verify:**
  - `B`.
  - `T(ProjectVaultQueueLivePhaseTests|ProjectVaultFriendsWorkflowTests|WorkflowDoneArchiveConfirmationTests|WorkflowDoneMetadataRefusalTests|KeepLocalReviewRequiredTests)`.
  - Then the full gates, because steps 2 to 5 change every Keep Local gate.

### Step 6: Close the raw set

- Make `VaultSettings.keepLocalProjectIDs` `internal`.
- The diagnostics exporter and the Review Keep Local sheet read `keepLocalPins.storedKeys.count`.
  The behavior is the same; the name now says what it counts.
- `vaultCanonicalPath` forwards to `KeepLocalPins.canonicalFolderPath`.
- Switch the `FeatureArchiveBrowserTests` seeds (6 files, 15 uses) to `keepLocalPins`.
- Add a source guard test: Sources may use `keepLocalProjectIDs` only in `AppSettings.swift`,
  `SettingsRepair.swift` and `KeepLocalPins.swift`. Add its row to the AGENTS.md rule table.
- **Verify:** `B`, then `T(FeatureArchiveBrowserTests|AppCoreTests)` and every `*SourceTests`.

### Step 7: Document, accept the ADR, full gates, live check

- Add a "Keep Local pins" ownership section to `docs/architecture.md`.
- Add a row to the state-owner table in `docs/architecture-map.md`.
- Set ADR 021 to Accepted — implemented, if the owner agrees. Replace its link to this plan with
  the commit range.
- Delete this plan file.
- **Verify:**
  - The full gates from Terminal.app.
  - The link check on the changed docs.
  - A live check with `verify-niko-music-hub`, Vault folders inside the run (see
    `features/project-vault.md`):
    1. Turn Keep Local on for a song, and confirm the card shows it.
    2. Choose "Keep on this Mac" for a Done song.
    3. Turn both off again.
    4. Read the run's settings suite: no key of those projects is left.

## Completion criteria

- `KeepLocalPins` is the only code that decides whether a project is pinned and which keys a pin
  writes or removes.
- In Sources, `keepLocalProjectIDs` appears only in `AppSettings.swift`, `SettingsRepair.swift` and
  `KeepLocalPins.swift`. The new source guard test enforces it.
- No Keep Local check builds a key set by hand: no `Set([ … standardizedFileURL … ])` next to a
  Keep Local comparison, and `keepLocalKeys(for:` no longer exists.
- One canonical folder rule for Keep Local; `vaultCanonicalPath` forwards to it.
- `KeepLocalPinsTests` prove "never match less", downgrade-safe writes and unpin scope.
- Existing tests pass. Only Keep Local seeds and helpers were edited.
- The full gates and the live check are green on the final commit.
- `docs/architecture.md`, `docs/architecture-map.md` and ADR 021 describe the owner. This plan is
  deleted.

## Follow-ups (not part of this plan)

- The wording of the Review Keep Local count ("N projects are currently pinned" counts keys).
  Possible fixes: drop the number, or count only new-style pins. This needs a product decision.
- Done eligibility (#7) could also check the catalog project ID. That needs a decision because it
  refuses more.
