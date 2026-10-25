# Decision: AppCore holds the shell kit; the Project Vault runtime is its own target

**Status:** Accepted — implemented (`ProjectVaultRuntime` target and `ProjectVaultRuntimeTests`; `ModuleBoundarySourceTests`)  
**Date:** 2026-10-25  
**Deciders:** Niko Music Hub owner (asked for the move on 2026-10-25) + implementation  
**Scope:** `Package.swift`, `Sources/AppCore`, `Sources/ProjectVaultRuntime`, `Tests/AppCoreTests/ModuleBoundarySourceTests.swift`

## Context

`AppCore` held two things: the shell kit every tool uses, and the Project Vault runtime
(`LiveProjectVaultRuntime`, its admissions, capacity probe, authorization, recovery bundle and
presentation, about 5k lines in `AppCore/ProjectVault/`). AGENTS.md said the runtime stays "until it
gets its own target", and the architecture map listed "What triggers moving the Project Vault runtime
out of AppCore?" as open question 3. Nothing said what else belongs in `AppCore`, so every new
subsystem had the same question.

The runtime has its own state owners (the runtime actor and its mutation lease, the transfer and
catalog stores it drives) and its own rules (admission, Keep Local, Emergency Stop, the bound archive
token). Its only users are `FeatureArchiveBrowser` (the Vault UI and queue) and the app target
(composition and the Project Vault settings pane). No other tool and no shell-kit code calls it. Two
shell-kit files named a runtime type: `ToolContext.recoveryService` (read only by the app target's
settings pane) and `ShellJobStatusCopy.vaultTransferStatus(songName:progress:)` (called only by the
archive feature).

## Decision

1. `AppCore` holds the shell kit: the tool registry and `ToolFeature` seam, `ToolContext`, settings
   (the stored model, including `VaultSettings` and `KeepLocalPins`, which the shell's settings repair
   and output guard also read), jobs and quit, the Output Inbox, diagnostics, the shared components and
   the helper tools. Shell code may name a kind of work (a Vault transfer row, its cancel target, its
   settings pane) without depending on the code that does it.
2. The test for leaving `AppCore`: a subsystem that has its own state owners and its own rules, and
   that is used only by one feature and the composition (the app target), gets its own target. It depends on `AppCore` and
   `NikoMusicCore`; `AppCore` never depends on it. If shell code needs one of its values, that value is
   shared settings model and stays in `AppCore`, or the shell reaches it through a protocol `AppCore`
   owns, and only when that protocol has a production and a test adapter.
3. The Project Vault runtime passes that test and is the target `ProjectVaultRuntime`
   (`Sources/ProjectVaultRuntime/`, tests in `Tests/ProjectVaultRuntimeTests/`). It also holds
   `VaultRootManager`, the Active/Archive root pairing rule, whose only caller is the app target.
   API names are unchanged; callers gained an `import`.
4. The two shell-kit edges go away without a new protocol:
   - `ToolContext.recoveryService` is removed. `AppComposition.vaultRecoveryService` reaches the
     Project Vault settings pane through the Settings scene, the way `AppUpdateController` does.
   - `vaultTransferStatus(songName:progress:)` and `vaultTransferFallback` are an extension of
     `ShellJobStatusCopy` in the runtime, beside `ProjectVaultRestoreProgress`.
5. The edges are enforced: the strict import check rejects an undeclared import, and
   `ModuleBoundarySourceTests` pins the runtime's imports to `AppCore`, `NikoMusicCore`, Foundation,
   Darwin and CryptoKit, and its importers to `FeatureArchiveBrowser` and the app target.

## Options

| Option | Complexity | Pros | Cons |
|---|---|---|---|
| A. Keep the runtime in `AppCore` | None | No churn | `AppCore` stays two modules in one; the shell kit can call the runtime by accident; the question stays open for every new subsystem |
| **B. Own target over `AppCore`, with a written test** | Low | One direction, enforced; `AppCore` is only the shell kit; the next subsystem has an answer | One more target and test target; two pieces of wiring move |
| C. Move the runtime into `FeatureArchiveBrowser` | Medium | One fewer target | The app target's settings pane and composition would import the feature for Vault types; the feature grows again while its view model is being split |

## Consequences

- `AppCore` no longer imports or names a runtime type. A shell-kit change cannot reach the Vault
  runtime without an edge that fails `ModuleBoundarySourceTests`.
- `AppCoreTests` and `FeatureArchiveBrowserTests` depend on `ProjectVaultRuntime` for the tests that
  cross the edge (settings with Vault refusals, Keep Local with an archive token, the archive's Vault
  queue). Runtime tests that check the stored Keep Local keys use `@testable import AppCore`; product
  code still goes through `KeepLocalPins` (ADR 021).
- The benchmark scripts that link `FeatureArchiveBrowser` objects also link `ProjectVaultRuntime`.

## Open

- No other subsystem in `AppCore` passes the test today. The helper tools have their own owner
  (`HelperToolHealth`) but three tools and the shell's Set Up sheet use them, so they stay.
