# Plan: One owner for the archive footer

**Status:** In progress — see [Progress](#progress)  
**Date:** 2026-10-22  
**Source:** finding 2 of the architecture review of 2026-10-22 (highest-ranked finding with high confidence)  
**Scope:** `Sources/FeatureArchiveBrowser` only. No other module, no UI copy, no settings format.

This plan keeps two kinds of statement apart. **Current** describes the code at `3bc0d67`.
**Planned** describes the target, which does not exist yet. When the plan is done, the lasting part
moves to [architecture.md](../architecture.md) and this file is deleted (see
[Completion criteria](#completion-criteria)).

## Progress

Resume from the first step that is not done. Each step is one commit on `main` (local, not pushed).

| Step | State | Commit | Checks |
| --- | --- | --- | --- |
| 0 Baseline | done | — | `./script/ci.sh` green at `3ace650` (Terminal.app, 2026-10-22). `3bc0d67` changed docs only, so no re-run. |
| 1 Footer type and tests | done | `git log --grep='(step 1)'` | strict build; `ArchiveFooterStatusTests` 13/13 |
| 2 View model stores the footer | done | `git log --grep='(step 2)'` | strict build; `FeatureArchiveBrowserTests` 631/631; all `*SourceTests` 88/88; full `ci.sh` at `9b24264` green (Terminal.app): XCTest 2,813, 0 failures, 8 skipped; Swift Testing 93 |
| 3 Root-access kind | done | `git log --grep='(step 3)'` | strict build; `FeatureArchiveBrowserTests` 631/631 |
| 4 Settings kind | done | `git log --grep='(step 4)'` | strict build; `FeatureArchiveBrowserTests` 631/631 |
| 5 Vault read kind, upload-wait withdraw | done | `git log --grep='(step 5)'` | strict build; `FeatureArchiveBrowserTests` 631/631 before the new test; new `testRefreshWithdrawsTheUploadWaitMessageOnlyWhenNoUploadIsPending` passes |
| 6 Song-details host callback | done | `git log --grep='(step 6)'` | strict build; `FeatureArchiveBrowserTests` 633/633 (with the new repair test) |
| 7 Remove temporary API, docs, full gates | not started | | |

## Revisions

1. **Step 1: plain warnings classify song-details sentences.** The plan had a separate
   `.songDetails(_:)` factory and an `.other(_:)` factory, and step 6 named three song-details
   producers. The code shows more: at least eight untyped paths report `SongMetadataIntegrityCopy`
   sentences (`+Collaborators.swift:32, 119`, `+Metadata.swift:274, 276`,
   `+ProjectVaultCatalog.swift:31`, `+Scan.swift:100, 112`, `+ScanHost.swift:93`, and the metadata
   coordinator). Today a repair replaces any of them because it checks the text. So the plain
   initializer `Warning(_ text:)` now classifies with `SongMetadataIntegrityCopy.isIntegrityWarning`.
   This keeps repair behavior identical by construction, and step 6 only changes the host callback.
2. **Step 2: the footer methods live in `ArchiveBrowserViewModel.swift`.** `private(set)` limits
   the setter to the declaring file, so `ArchiveBrowserViewModel+StatusMessages.swift` was merged
   into the main file ("Footer status" extension) and deleted. Root reset uses the permanent
   `clearFooterWarning()`.
3. **Step 2: publish only on change.** Every footer method goes through `updateFooter`, which
   assigns `footer` only when the value changed. Before, every setter published, even a background
   message that a Vault hold ignored. The text the view shows is unchanged.
4. **Step 2: two more test edits.** `ArchiveBoardSongsViewTests.swift:30` and
   `ArchiveBrowseRefreshDriverTests.swift:21` assigned `statusMessage` directly; they now call
   `setBackgroundStatusMessage`. `ArchiveSettingsRepairTests.swift:115` now records an unrelated
   warning instead of assigning nil, which still proves that onboarding records the settings
   warning again.

5. **Step 5: a test for the upload-wait withdraw.** No existing test checked that the upload-wait
   message clears only when no upload is pending and only while it is on show. The condition was
   rewritten in this step, so `ArchiveVaultObservationTests` gained
   `testRefreshWithdrawsTheUploadWaitMessageOnlyWhenNoUploadIsPending`. The view model gained
   `withdrawFooterMessage(_:)` because `footer` is `private(set)`.

6. **Step 6: a test that a repair keeps unrelated warnings.** The existing repair test checks that a
   stale song-details warning clears; nothing checked the opposite. `SongMetadataRepairTests` gained
   `testRepairRefreshLeavesOtherFooterWarningsAlone`. The host callback is implemented by the new
   view-model method `refreshSongDetailsWarning(_:)`.

## Terms

| Term | Meaning | Today's name in code |
| --- | --- | --- |
| Archive footer | The caption row under the Archive Browser: the search count plus one status text (`ArchiveBrowserView.swift:135-150`) | "footer" (comments, architecture.md) |
| Footer message | The main sentence, for example "Scanned 9 songs." | `statusBaseMessage` |
| Footer warning | The sticky sentence appended after the message. It is not limited to persistence. | `persistenceWarningMessage` |
| Message source | Who speaks: an **action** the person took, a **background** scan, or the **Project Vault** | implicit in which setter is called |
| Warning kind | The family a warning belongs to, so code can clear it without reading its text | none (text matching) |

## Current architecture (observed at `3bc0d67`)

Four loose stored properties on `ArchiveBrowserViewModel` make up the footer:

- `statusMessage` (`@Published`, read by `ArchiveBrowserView`)
- `statusBaseMessage`
- `persistenceWarningMessage`
- `projectVaultOwnsStatus`

The rule lives in `ArchiveBrowserViewModel+StatusMessages.swift`:

- The displayed text is `message + " " + warning`.
- A Project Vault message holds the footer. A background message is ignored while the Vault holds
  it, and any action message releases the hold.
- A new warning replaces the old one.

The four setters, with production call counts:

| Setter | Calls |
| --- | --- |
| `setStatusMessage` | 25 |
| `setProjectVaultStatusMessage` | 54 |
| `setBackgroundStatusMessage` | 8 |
| `recordPersistenceWarning` | 29 |

Where the rule leaks:

1. **Direct writes bypass the funnel.** Each writer re-derives the text by hand:
   - `+Roots.swift:98-99, 419-420`
   - `+ProjectVault.swift:190-191`
   - `+Scan.swift:48`
   - `ArchiveBrowserViewModel.swift:207`: `setPersistenceWarningDirect` does not re-derive at all.
2. **Warnings are identified by their text:**
   - `hasPrefix("Archive settings could not be")` (`+Roots.swift:96`)
   - `hasPrefix("Archive root access could not be restored:")` (`+Roots.swift:417, 631`)
   - Exact equality with two Vault strings (`+ProjectVault.swift:188-189`)
   - `SongMetadataIntegrityCopy.isIntegrityWarning(current)` inside the metadata coordinator
     (`ArchiveMetadataEditingCoordinator.swift:522`)
   - The root-access sentence alone is written in 5 places (`+Roots.swift:72, 485, 563, 579, 625`).
3. **The footer is read back as data:**
   - The metadata coordinator reads the current warning (`currentPersistenceWarning`).
   - The Vault refresh compares the message with the upload-wait text (`+ProjectVault.swift:193`).
   - `removeRoot` stashes and re-raises warnings by prefix (`+Roots.swift:616-633`).
4. **Bug history:**
   - `f4d563c`: Undo of a paused Done left a stale Vault message.
   - `55facd6`: a scan wiped a Vault message.

## Design A — `ArchiveFooterStatus` value type (chosen)

Move the footer's state, its rule and the identity of its warnings into one value type. Keep
today's behavior exactly.

```swift
/// What the archive footer shows: at most one message and one warning.
///
/// A Project Vault message holds the footer until the next action message;
/// background messages never replace it. A new warning replaces the old one.
/// `text` is the message, then the warning, separated by one space.
struct ArchiveFooterStatus: Equatable {
    enum Source: Equatable { case action, background, projectVault }

    struct Warning: Equatable {
        enum Kind: Equatable { case settings, rootAccess, projectVaultRead, songDetails, other }
        let kind: Kind
        let text: String
    }

    private(set) var message: String?
    private(set) var warning: Warning?
    var text: String? { get }

    mutating func show(_ message: String?, from source: Source)
    mutating func raise(_ warning: Warning)
    /// Clears the warning only when it is of this kind.
    mutating func resolve(_ kind: Warning.Kind)
    /// Clears any warning (root change).
    mutating func clearWarning()
    /// Clears the message only while it is still exactly `message`; the Vault keeps the hold.
    mutating func withdraw(_ message: String)
}
```

A factory next to each warning family owns that family's sentence, so the copy and its identity
sit in one place:

| Factory | Kind | Replaces |
| --- | --- | --- |
| `.rootAccess(rootName:)` | `rootAccess` | 5 hand-written sentences and 2 prefix checks |
| `.settingsLoadFailed(_ error:)`, `.settingsSaveFailed(_ error:)` | `settings` | `+Roots.swift:84, 167-170` and the prefix check |
| `.archiveWriteRefused(_ error:)` | `settings` for `ArchiveWriteGuardError.settingsUnreadable`, else `other` | `+Roots.swift:467` and the equality check at `:97` |
| `.projectVaultUnreadable(recordsOnly:)` | `projectVaultRead` | the two statics in `+ProjectVault.swift:225-226` and their equality check |
| `Warning(_ text:)` (plain initializer) | `songDetails` when `SongMetadataIntegrityCopy.isIntegrityWarning(text)`, else `other` | the classifier call inside the coordinator, and every other warning (about 20 sites) |

The plain initializer keeps the existing prefix classifier on purpose (revision 1). `SongMetadataIntegrityCopy`
writes those sentences and owns the classifier in the same file
(`ArchiveCatalogCoordinator.swift:125-135`). Reusing it keeps today's behavior exactly, including
for `storageUnavailable`.

## Design B — per-source slots (considered, not chosen)

This is the shape the review card sketched. It keeps separate slots for `action`, `background`
and `projectVault`, plus a map of warnings by kind. The text shows the highest-precedence message,
followed by every active warning.

What it would add:
- A warning no longer hides another warning.
- A background message is kept while the Vault holds the footer, and reappears afterwards.
- The `removeRoot` stash and re-raise logic goes away.

Why it is not chosen:
- **It needs rules that nobody has stated.** When does each slot clear? Does a Vault message
  survive a later action message (today: no)? In what order do several warnings show? Each answer
  is a product decision, and every one of the 87 message callers would have to learn its slot's
  clearing duty.
- **Several warnings make the footer longer.** That collides with the binding rule that text in a
  fixed slot fits without clipping (AGENTS.md, design contract).
- **It changes visible output.** The 117 `statusMessage` references in `FeatureArchiveBrowserTests`
  would need review for intended changes, not refactoring noise.
- **It does not prevent the recorded bugs either.** `f4d563c` was a missing message after Undo,
  not a slot conflict.

Revisit B only when a real report shows one warning hiding another.

## Comparison

| | A: one owner, same rules | B: per-source slots |
| --- | --- | --- |
| Depth | Small interface (5 mutations, `text`) that enforces the rule and the warning identities | Larger interface (set and clear per slot); clearing decisions move to callers |
| Locality | Rule, composition and resolvable copy live in one file | The same, but the rules themselves are new |
| Caller knowledge | Unchanged: pick a source; pick a warning factory | Grows: each caller also owns when its slot clears |
| Behavior change | None intended | Visible, needs product decisions |
| Seam | None. A pure value type with one implementation needs no protocol | None |
| Test surface | `ArchiveFooterStatusTests` on the value type, plus the existing view-model tests unchanged | The same, plus re-baselining copy assertions |

**Decision: A.** It removes the text-as-identity coupling and the scattered invariant. It adds no
rule that the product has not asked for.

## Planned architecture

### Target responsibilities

| Responsibility | Current owner | Planned owner |
| --- | --- | --- |
| Compose message and warning into the footer text | Each writer, via `combinedStatusMessage` | `ArchiveFooterStatus.text` |
| Vault hold rule (background yields, action releases) | `projectVaultOwnsStatus` and 4 setters | `ArchiveFooterStatus.show(_:from:)` |
| Warning identity and clearing | Text matches in 4 files | `Warning.Kind` and `resolve(_:)` |
| Copy of resolvable warnings | 5 + 2 + 2 hand-written strings in `+Roots`, `+ProjectVault` | One factory per family |
| "Is the current warning a song-details warning?" | `ArchiveMetadataEditingCoordinator` reads the footer | The view model, inside the host callback |
| Choose what to say and which source | Callers | Callers (unchanged) |
| Per-song Vault operation messages | `ProjectVaultOperationCoordinator` | Unchanged; it reads `footer.message` through the existing callback |

### Public interfaces

Everything stays `internal` to `FeatureArchiveBrowser`.

- **New:** `ArchiveFooterStatus` (above), in `Sources/FeatureArchiveBrowser/ArchiveFooterStatus.swift`.
- **`ArchiveBrowserViewModel`:**
  - `@Published private(set) var footer: ArchiveFooterStatus` replaces the four stored properties.
  - `statusMessage`, `statusBaseMessage` and `persistenceWarningMessage` become get-only computed
    properties over `footer`. `ArchiveBrowserView` and existing tests keep reading them.
  - `setStatusMessage`, `setProjectVaultStatusMessage` and `setBackgroundStatusMessage` keep their
    names and signatures; each becomes a one-line `footer.show`. The `ArchiveScanHost` protocol does
    not change.
  - `recordPersistenceWarning(_ text: String)` stays, meaning `Warning(text)`. A new overload
    `recordPersistenceWarning(_ warning: ArchiveFooterStatus.Warning)` takes typed warnings.
  - New: `resolveFooterWarning(_ kind:)`.
  - Removed: `combinedStatusMessage(base:)` and `projectVaultOwnsStatus`.
- **`ArchiveMetadataEditingHost`:** `currentPersistenceWarning` and `setPersistenceWarningDirect`
  are replaced by one callback, `refreshSongDetailsWarning: (String?) -> Void`. It means: "if the
  footer warning is a song-details warning, replace it with this text, or clear it when nil."

### Dependency direction

```text
ArchiveBrowserView ──reads──► ArchiveBrowserViewModel.statusMessage (computed)
ArchiveBrowserViewModel ──owns──► ArchiveFooterStatus
ArchiveFooterStatus ──uses──► SongMetadataIntegrityCopy.isIntegrityWarning, ArchiveWriteGuardError   (leaf types, same module)
ArchiveMetadataEditingCoordinator ──calls──► host callbacks (no longer reads footer state)
```

`ArchiveFooterStatus` imports only Foundation. It does not know the view model, the coordinators
or the Vault runtime.

## Behavior and compatibility requirements

1. **The footer text is identical for every sequence of calls that exists today.** That covers
   the composition, the Vault hold, warning replacement, and every clear condition.
2. **Every warning sentence is byte-for-byte unchanged.** Factories produce the exact strings that
   are written inline today.
3. **The clear rules are unchanged:**
   - Settings repair clears the warnings that today match the `"Archive settings could not be"`
     prefix or `ArchiveWriteGuardError.settingsUnreadable`.
   - A successful Vault snapshot read clears only the two Vault-read warnings.
   - Root recovery and root removal clear only root-access warnings.
   - A song-details repair replaces only warnings that `isIntegrityWarning` classifies.
   - A root change clears every warning.
4. **The Vault upload-wait message** is withdrawn only while it is still the current message and
   no transfer still waits for upload (`+ProjectVault.swift:193-196`).
5. **`removeRoot` keeps an unrelated warning visible** after a root removal (today's stash
   behavior).
6. **No change to public API, settings, storage, the UI layout, or other modules.**
7. **Out of scope** (each needs its own decision):
   - Renaming `recordPersistenceWarning` and `persistenceWarningMessage`. This is cosmetic.
   - Replacing the collaborator "warning before/after" comparison in
     `+Collaborators.swift:18-26`. That needs `MetadataCommitOutcome` to say whether a refusal
     reported a warning. The comparison keeps working on the typed `footer.warning`.
   - Per-song operation messages in `ProjectVaultOperationCoordinator`.

## Steps

Each step builds with no warnings and leaves every existing test green. Do the steps in order,
with one commit per step.

**Verification commands used below:**
- `B`: `swift build --build-tests --explicit-target-dependency-import-check error`
- `T(...)`: `swift test --filter '<suites>'`

Run the full gate from Terminal.app, because the recorder probe tests are unreliable in an agent
shell.

### Step 0: Baseline

- Run `./script/ci.sh` at the starting commit and record the result. It was green at `3bc0d67`'s
  parent `3ace650` on 2026-10-22.
- **Verify:** exit 0.

### Step 1: Add `ArchiveFooterStatus` and its tests (not wired)

- Add the type with `show`, `raise`, `resolve`, `clearWarning`, `withdraw`, `text`, and all
  warning factories.
- Add `Tests/FeatureArchiveBrowserTests/ArchiveFooterStatusTests.swift`. It covers:
  - **Precedence table:** action / background / Vault, in every order of two calls.
  - **Composition:** message only, warning only, both, and an empty message.
  - **Warnings:** replacement; `resolve` clears only a matching kind; `clearWarning`.
  - **`withdraw`:** it clears only an exact current message and keeps the Vault hold.
  - **Factory texts:** equal to today's literals, copied into the test as expected values.
  - **Classification:** `.songDetails` and `.archiveWriteRefused` classify exactly like today's
    checks.
- **Verify:** `B`, then `T(ArchiveFooterStatusTests)`.

### Step 2: The view model stores the footer

- Replace the four stored properties with `footer`. Make `statusMessage`, `statusBaseMessage` and
  `persistenceWarningMessage` get-only computed properties.
- The three message setters and `recordPersistenceWarning(String)` forward to `footer`. Every
  string warning goes through `Warning(text)` at this step (revision 1).
- Convert the five direct writes **without changing behavior**. They now call a temporary
  `footer.removeWarning(where:)`, which keeps today's text predicates:
  - `+Scan.swift:48` becomes `clearWarning()`.
  - `+Roots.swift:98-99` and `:419-420` keep their prefix predicates.
  - `+ProjectVault.swift:190-191` keeps its equality predicate.
  - `ArchiveBrowserViewModel.swift:207`: the host's direct setter now sets the warning through the
    footer, which re-derives the text immediately. The final text after `reportStatus` is
    unchanged.
- `removeRoot` stashes `footer.warning` (typed) instead of the string.
- Update the one test that assigns the warning: `ArchiveSettingsRepairTests.swift:115`.
- **Verify:**
  - `B`.
  - `T(ArchiveBrowserViewModelTests|ArchiveSettingsRepairTests|ArchiveMultiRootRecoveryTests|ArchiveVaultObservationTests|CollaboratorAuditRegressionTests|KeepLocalReviewRequiredTests|ArchiveMetadataEditingOwnerTests|ArchiveAccessRecoveryTests|ArchiveActiveRootRecoveryTests|ArchiveRootBookmarkPersistTests|ProjectVaultFriendsWorkflowTests)`.
  - Then the full `./script/ci.sh`, because this step touches the most call sites.

### Step 3: Root-access warnings get a kind

- The five sentences in `+Roots.swift` use `.rootAccess(rootName:)`.
- `clearStaleArchiveRootAccessWarning` uses `resolveFooterWarning(.rootAccess)`.
- The `removeRoot` stash compares `kind != .rootAccess`.
- Delete both prefix predicates.
- **Verify:** `B`, then `T(ArchiveMultiRootRecoveryTests|ArchiveAccessRecoveryTests|ArchiveActiveRootRecoveryTests|ArchiveRootBookmarkPersistTests|ArchiveFooterStatusTests)`.

### Step 4: Settings warnings get a kind

- `+Roots.swift:84` uses `.settingsLoadFailed`.
- `recordArchiveSettingsSaveFailure` uses `.settingsSaveFailed`.
- `+Roots.swift:467` uses `.archiveWriteRefused`.
- `applyRepairedSettings` uses `resolveFooterWarning(.settings)`.
- Delete the prefix and equality predicate.
- **Verify:** `B`, then `T(ArchiveSettingsRepairTests|ArchiveMultiRootRecoveryTests|ArchiveFooterStatusTests)`.

### Step 5: Project Vault read warnings and the upload-wait message

- `recordProjectVaultReadFailure` uses `.projectVaultUnreadable(recordsOnly:)`.
- The snapshot refresh uses `resolveFooterWarning(.projectVaultRead)`, and
  `footer.withdraw(ProjectVaultActivityExplanation.transfer(.awaitingProviderDurability))` under
  the existing upload condition.
- Delete the two statics. Point `ArchiveVaultObservationTests.swift:366` at the factory text.
- **Verify:** `B`, then `T(ArchiveVaultObservationTests|ArchiveBrowserViewModelTests|ArchiveSettingsRepairTests|ProjectVaultQueueLivePhaseTests|ProjectVaultFriendsWorkflowTests|ArchiveFooterStatusTests)`.

### Step 6: Song-details warnings and the metadata host

- String warnings already classify song-details sentences through `Warning(text)` (revision 1),
  so no producer changes.
- Replace `currentPersistenceWarning` and `setPersistenceWarningDirect` with
  `refreshSongDetailsWarning`. Update `repairSongMetadata`
  (`ArchiveMetadataEditingCoordinator.swift:522-523`) and the two test harnesses in
  `ArchiveMetadataEditingOwnerTests.swift:57-58, 515-516`.
- **Verify:** `B`, then `T(ArchiveMetadataEditingOwnerTests|SongMetadataRepairTests|SongMetadataStorageUnavailableTests|WorkflowDoneMetadataRefusalTests|ArchiveBrowserViewModelTests|ArchiveFooterStatusTests)`.

### Step 7: Remove the temporary API; document the owner

- Delete `removeWarning(where:)` and `combinedStatusMessage`.
- Add an "Archive footer ownership" section to `docs/architecture.md`. It states the rule, the
  warning kinds, and one line on why per-source slots were not chosen (Design B above).
- Add a row to the state-owner table in `docs/architecture-map.md`.
- Delete this plan file.
- **Verify:**
  - `B`.
  - The full `./script/ci.sh` from Terminal.app.
  - `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh` from Terminal.app, because the footer is
    visible text.
  - The link check on the changed docs.

## Completion criteria

- `ArchiveFooterStatus` is the only place that composes the footer text, applies the Vault hold
  and decides warning identity.
- `ArchiveBrowserViewModel` has no stored footer fields. `statusMessage`, `statusBaseMessage` and
  `persistenceWarningMessage` are get-only, so a direct write no longer compiles.
- No code identifies a footer warning by its text:
  - `grep -rn 'hasPrefix("Archive' Sources/FeatureArchiveBrowser` finds no warning checks.
  - `projectVaultReadFailureMessage`, `currentPersistenceWarning`, `setPersistenceWarningDirect`
    and `projectVaultOwnsStatus` no longer exist.
  - `isIntegrityWarning` is called only by the `.songDetails` factory.
- Each resolvable warning sentence is written exactly once.
- `ArchiveFooterStatusTests` cover precedence, composition, resolve and withdraw.
- Existing tests pass. Only these were edited:
  - `ArchiveSettingsRepairTests.swift:115`
  - `ArchiveVaultObservationTests.swift:366`
  - the two `ArchiveMetadataEditingOwnerTests` harnesses
- `./script/ci.sh` and the strict E2E smoke are green from Terminal.app on the final commit.
- `docs/architecture.md` and `docs/architecture-map.md` describe the new owner. This plan is
  deleted.

## Why no ADR

The decision is local to one feature and does not limit other modules. Its lasting rationale is one
line: per-source slots were not chosen because they need clearing rules nobody has stated, and
because several warnings conflict with the fixed-slot text rule. That line goes into the ownership
section of `docs/architecture.md` in step 7, where the other ownership rationale already lives
(Project Vault operation ownership, metadata editing ownership). Write an ADR if a later change
reopens Design B.
