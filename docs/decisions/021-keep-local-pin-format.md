# Decision: Keep Local pins keep their stored format; one module owns matching

**Status:** Accepted — implemented (`6ae71fb`..`63630fd`; `KeepLocalPins`, `KeepLocalPinsTests`, `KeepLocalPinsSourceTests`); keys private to `KeepLocalPins` since 2026-10-25  
**Date:** 2026-10-22  
**Deciders:** Niko Music Hub owner (approved 2026-10-22) + implementation  
**Scope:** `VaultSettings.keepLocalProjectIDs`, `KeepLocalPins` (AppCore), every Keep Local check in the Project Vault runtime and the archive browser

## Context

Keep Local pins protect a project's Active folder from removal by the Project Vault. They are stored
as one set of strings in settings, `keepLocalProjectIDs`. The set mixes catalog project IDs, song IDs
and folder paths in several spellings (raw, standardized, symlink-resolved, canonical). Ten places
build their own key set and compare it with the stored set. Each picks different members. Two fixes
on 2026-10-16 came from keys that did not match: L106 (`767bbff`) and L048 (`cda1936`).

The obvious clean-up is to store typed pin records instead. That changes data that older builds and
Project Vault recovery bundles read.

## Decision

1. The stored format stays: the same settings key, the same `Set<String>` shape, and keys in the
   spellings older builds compare.
2. One AppCore value type, `KeepLocalPins`, owns:
   - matching: IDs exactly, folders by one canonical folder path
   - which keys a pin writes
   - which keys unpin removes

   Every Keep Local check and write goes through it. The raw set becomes `internal` to AppCore.
   (2026-10-25: the keys are `private` to `KeepLocalPins`. `VaultSettings.keepLocalPins` stores the value,
   which encodes itself as the same array under the same key, so a read or build of the keys outside
   `KeepLocalPins.swift` does not compile.)
3. A pin writes at least every spelling an older build compares. Matching never reports "not
   pinned" where an older check reported "pinned".

## Options

| Option | Complexity | Pros | Cons |
| --- | --- | --- | --- |
| **A. One module over the same storage** | Low | One owner for matching; no data change; downgrade-safe | Old keys still cannot be grouped per project |
| B. Typed pin records and a migration | Medium | Honest representation; exact counts for new pins | An older build or an older recovery-bundle import sees no pins, so the Vault could remove a pinned project; dual-write adds a second store to keep in step; the migration freezes the current filesystem state; old keys still cannot be grouped |
| C. A shared key-builder function | Low | Removes the spelling lists | Callers keep the set algebra and the unpin filter, so the bug class stays |

## Consequences

- An older build after a downgrade, and recovery bundles in both directions, keep reading every pin.
- Matching becomes at least as strict as before. A pin under another spelling of the same folder now
  counts everywhere. That is the fail-safe direction.
- An exact project count stays impossible for existing pins. The Review Keep Local sheet counts
  stored keys; its wording is a separate product decision.
- A future proposal to store typed pins must solve downgrade and recovery-bundle compatibility
  first. Reopen this decision for that.

## Open

- The wording of the Review Keep Local count.
- Whether Done eligibility should also check the catalog project ID (it refuses more).
