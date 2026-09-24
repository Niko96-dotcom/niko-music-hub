# Vault durability contract (local)

How the Project Vault proves a local archive generation is durable **before**
anything may authorize removal of the Active copy — and what that proof does
not mean.

## Rule

No Active copy is removed on the strength of a completed copy/rename. A
completed copy proves bytes reached the page cache; it is not durability
evidence. `LocalFolderArchiveStorage.waitUntilDurable` runs the local
persistence barrier (`Sources/NikoMusicCore/Vault/LocalVaultDurabilityBarrier.swift`)
and returns `.verifiedLocal` only when the full sequence below succeeded. Any
failure throws fail-closed, preserves every byte, and reports a clear blocked
reason. Vault functionality is never disabled to hide a missing proof, and a
missing proof never authorizes deletion.

## User-visible workflow

- Archiving intent is **Keep a verified copy** or **Archive and free up space**. It replaces the earlier rollout selector in the UI; the legacy value is retained for existing records. Choosing copy-only never gains removal later through a settings change.
- Background scheduling is off by default and opted in independently from manual archiving.
- Song completion offers **Archive and free up space** (only when permitted), **Keep a verified copy**, **Keep on this Mac**, or **Keep Status**, with the same shared manual confirmation on the board and in song detail.
- Delayed retries stay copy-only. A verified archive with persisted recovery evidence can offer **Ready to free space** under a fresh confirmation.
- Copies, pending transfers, and failures stay on the board. Archive-only songs stay hidden until shown again.
- Restoring preserves the song's workflow stage and pins Keep Local before any copy or open. **Resume work** explicitly moves the song to the existing **Prod** stage.
- A disabled Vault keeps its configured Active and Vault roots off the board until re-enabled. A paused restore stays paused until explicitly unpaused.
- Recovery copies are metadata-only (catalog plus settings) and stay available while Vault is off. See [Project Vault recovery copies](vault-recovery.md).

## Pending cloud uploads

A File Provider upload that exceeds a bounded check stays pending, rather than
becoming a failed transfer. The transfer journal retains the staging or promotion
phase and schedules another check after 60 seconds. The mounted browser runs that
check automatically; relaunch recovery also respects the persisted deadline.
These waits do not consume the failure retry budget or recopy the project.
Provider errors still use the existing bounded failure recovery policy, and
cancellation remains an explicit stop. Emergency Stop suspends automatic recovery.

The Active source remains intact throughout. Background recovery verifies both
provider barriers and the final generation content, then stops at `archiveVerified`.
It does not persist or reuse an old Active-removal authorization: removal still
requires the existing fresh confirmation and safety checks.

## Barrier sequence (local generations)

For a staging or promoted generation directory inside the configured archive
root, in order:

1. **Qualify the volume.** Descriptor `fstatfs` filesystem type must be one
   of the supported names (see table; `Darwin.statfs` is not addressable as a
   function on the actual Swift SDK, so the barrier opens with
   `O_RDONLY | O_CLOEXEC | O_NOFOLLOW` and calls `fstatfs`). Anything else
   throws `unsupportedFilesystem` before any flush is attempted. The terminal
   drain re-qualifies on the drain descriptor itself (same fd as the drain
   `fstat` via the `filesystemTypeOfDescriptor` seam): a volume replacement
   between start and drain that reports an unqualified type throws
   `unsupportedFilesystem` instead of `.verifiedLocal`, and the device drain
   never runs.
2. **Confine the tree.** The requested (standardized, unresolved) path must
   be contained in the archive root with no nested symlinks (`PathSafety`
   per-component `lstat` walk), otherwise `locationOutsideArchiveRoot`.
   Resolving before this check would hide a nested symlink in the requested
   prefix. Only the well-known `/tmp`→`/private/tmp` and `/var`→`/private/var`
   alias spellings are normalized for this check, so a legitimate user
   spelling confines while nested symlinks still throw `symlinkEscape`.
   Every node encountered must be a regular file or directory —
   symlinks throw `symlinkEscape`, anything else throws `unexpectedNodeType`.
3. **Bind every node to a device+inode identity.** Each node's `st_dev` plus
   `st_ino` (seam-observed at traversal, re-verified with `fstat` on the
   opened descriptor at flush time) must match, so a mid-traversal volume
   replacement or same-device same-type path replacement throws
   `deviceMismatch` instead of flushing the wrong object. Ancestors are
   snapshotted the same way before their own flush. Opens use
   `O_RDONLY | O_NOFOLLOW | O_CLOEXEC` (`O_DIRECTORY` for directories), so a
   symlink swapped in after traversal fails with `ELOOP` → `symlinkEscape`.
4. **Sync files, then directories, then ancestors.** `fsync` every regular
   file (path order), then `fsync` directories deepest-first including the
   generation root, then `fsync` the promotion ancestors from the generation
   parent inside-out through (and including) the archive root, so the final
   rename entry is persisted too. A generation equal to the archive root
   traverses the full tree (no root-only shortcut). Ancestors above the
   archive root are never synced here: if the storage folder predates the
   record, their durability is an external assumption, not a proven claim.
   Identity comparisons normalize the `/var` vs `/private/var` spelling split
   explicitly rather than assuming `resolvingSymlinksInPath()` makes strings
   identical.
5. **One terminal drain.** A single `F_FULLFSYNC` on the archive root (same
   `st_dev` and same qualified filesystem type, both verified at open on the
   drain descriptor) after all `fsync`s. Per XNU `fcntl(2)` it
   drains the device queue, so previously synced data on that device persists
   on success; one drain replaces per-file drains without weakening the claim.
6. **No downgrade.** A failed terminal drain reports `fullSyncFailed` even
   when every `fsync` succeeded. `CancellationError` propagates unwrapped so
   callers keep cancellation semantics. Bounded memory (paths plus two
   integers per node, never file contents) and no-delete hold throughout.

## Supported filesystems and provider qualification

| Filesystem (`statfs` name) | Local barrier status |
|---|---|
| APFS (`apfs`), HFS+ (`hfs`), FAT (`msdos`), UDF (`udf`) | Qualified: `F_FULLFSYNC` documented by XNU `fcntl(2)` |
| exFAT (`exfat`), NFS (`nfs`), SMB (`smbfs`), anything else | **Unqualified**: barrier throws `unsupportedFilesystem`, archive copy kept, Active copy kept |

Unqualified is a blocked transfer with a clear reason, not a disabled
feature: the engine maps the error to `failedRecoverable`/`recoveryRequired`
and all copies stay for review/retry.

The **cloud (File Provider) contract is distinct**. `FileProviderArchiveStorage`
proves provider sync (upload/materialization state) and returns
`.syncedToProvider`; the local barrier makes no claim about remote upload,
and provider sync makes no claim about local flush. Never present local
barrier success as remote sync, or vice versa.

## Barrier success is not a hardware guarantee

Barrier success means the operating system accepted the full sequence
(`fsync`s then one terminal `F_FULLFSYNC`) on a qualified local filesystem.
It does not guarantee hardware power-loss survival: drives may ignore flush
requests, and only the hardware vendor's contract governs the platters
(Apple documents strong persistence as a best-effort hardware contract with
I/O cost). No test in this repository performs a power-cut test — such proof
would require reboots and drive disconnects, which are out of scope.

## SQLite transfer state is recovery evidence

Launch recovery and Active-copy removal trust the persisted transfer records,
so `SQLiteArchiveDatabase` (`Sources/NikoMusicCore/Persistence/SQLiteArchiveDatabase.swift`)
separates configured durability from verified persistence:

- WAL journal mode (verified by read-back, as before);
- `synchronous = FULL` and `fullfsync = ON` on **every** connection
  (per-connection settings), failing closed at open time unless
  `synchronous` reads back FULL (2). Unknown pragmas silently do nothing, so
  the read-back is configuration evidence only — never proof the syscall
  completed. SQLite may fall back from a failed `F_FULLFSYNC` even when the
  pragma is requested;
- `fullfsync` read-back observed via `configuredDurability()` (0/1) without
  failing the catalog open: failing open on an unqualified volume would hide
  readable recovery records. Inability to prove persistence blocks
  destructive admission, never read-only catalog/recovery access. Open
  enforces no directory/file sync: creating the parent directory at init is
  best-effort only, and only the immediate parent is ever synced (in the
  explicit barrier below). Ancestors above it — including a pre-existing
  storage folder's parents — are an external assumption, not a proven claim;
- strict explicit barrier `proveRecoveryPersistence()` for recovery evidence
  before destructive removal: connection-file binding check, strict
  `wal_checkpoint(TRUNCATE)` with busy-row verification (`SQLITE_OK` alone
  can contain a busy row, so busy must be 0, frame counts must be
  non-negative — a non-WAL/inapplicable `-1 == -1` row is not proof — and
  every log frame checkpointed, otherwise fail closed; syncing the WAL file
  alone does not replace the checkpoint), then `fsync` + `F_FULLFSYNC` on
  the database file and its `-wal` sidecar when present, each on a descriptor
  bound to its expected identity (`fstat` vs the open-time connection binding
  for the main file, vs a freshly captured sidecar identity for the `-wal`,
  checked BEFORE any flush so a replacement present at open cannot be flushed
  and hidden by a later restore), then `fsync` + `F_FULLFSYNC` on the
  immediate parent directory only after binding the database file relatively
  (`openat`/`fstat` of the database name from the directory descriptor
  matches the same main binding) and confirming the directory is on the same
  device (files-then-dir, so new WAL/file entries are persisted before their
  directory entries). The binding is a device/inode identity captured at open
  (`sqlite3_db_filename` + `stat` + required `SQLITE_FCNTL_HAS_MOVED`;
  unsupported/error fails closed while the catalog stays readable, supported
  macOS VFS success retains proof) and rechecked before/after the checkpoint
  and before/after every file/directory sync: a same-path replacement keeps
  the filename string identical while SQLite keeps the original inode open,
  so path-string equality is necessary but never sufficient — a device/inode
  mismatch, a moved report, an unavailable `HAS_MOVED` report, a `stat`
  inability, a missing open-time binding, a descriptor `fstat` mismatch at
  open, or a relative `openat` mismatch fails closed instead of flushing an
  unrelated replacement file and claiming proof. A lazy reopen captures a
  fresh binding; reusing the live connection never re-binds, so concurrent
  replacement stays visible. The one-time best-effort VACUUM runs before the
  init-time capture, so a VACUUM rewrite does not stale the binding. A scoped
  `SQLiteRecoverySyncSeam` (`checkpointMainDatabase` /
  `synchronizeFile` (file URL plus its expected identity) /
  `synchronizeDirectory` (directory URL plus the main binding plus the
  database file name for the relative check), default `.live`) lets the
  engine consumer and tests fail the journal sync deterministically and assert
  fail-closed handling without touching real volumes. Honest limits: the
  open-time `stat` is immediately after `sqlite3_open`, not atomic with it
  (path `stat` alone cannot bind the actual connection across that race, so
  an unavailable `HAS_MOVED` report fails closed); success means the OS
  accepted the file-level sequence, not a hardware power-loss guarantee
  (drives may ignore flush requests); only the immediate parent directory is
  synced and only the main database file identity is bound plus the `-wal`
  sidecar identity captured at proof time — ancestors above the immediate
  parent (including a pre-existing storage folder's parents) and the `-shm`
  sidecar identity are external assumptions, not proven claims; a replacement
  after the final recheck and before the engine's delete is outside this
  barrier (the engine must call it immediately before authorizing deletion);
- `SQLiteVaultTransferStore` shares this database, so transfer records
  inherit the configuration with no migration (pragmas apply at each open).

Performance: FULL adds one sync per commit in WAL plus the explicit barrier
cost at destructive admission. Transfer records are low-frequency writes, but
no read/write-throughput impact is asserted here: capture before/after
transfer-path timings when touching this pragma set.

## Capabilities note

`LocalFolderArchiveStorage.capabilities().waitsForDurability` stays `false`
as a frozen contract (pinned by
`LocalVaultTransferEngineTests.testLocalFolderProviderReportsOnlyVerifiedLocalDurability`;
no production code branches on the flag). `waitsForDurability` means remote
asynchronous durability (provider upload/sync, as
`FileProviderArchiveStorage` reports `true`); it does not mean "no wait at
all". Local `waitUntilDurable` always blocks on the barrier flush above —
callers must not skip it based on the flag.

## Tests

Focused faults: `Tests/NikoMusicCoreTests/LocalVaultDurabilityTests.swift`

- nested ordering (files → deepest-first dirs → inside-out ancestors, then
  one terminal root drain qualified on the drain fd itself), empty tree,
  root-equals-generation full-tree traversal, file/dir symlink escapes,
  ancestor symlink traversal, out-of-root location, `/tmp` user spelling
  accepted while a nested symlink under the same spelling still throws
  `symlinkEscape`, unsupported filesystem, filesystem-type drift at drain
  (`unsupportedFilesystem`, device drain never runs), device mismatch,
  deterministic same-device file and ancestor inode replacement (fake inode
  with original kept allocated; normalized `/var` vs `/private/var` identity
  so each fault fires), file/directory sync failure, terminal-drain
  no-downgrade, sync failure skips drain, cancelled barrier, real-temp-fixture
  live syscall acceptance, provider barrier wiring (success + failure
  preserving bytes), SQLite FULL/fullfsync read-back + reopen +
  configured-vs-verified split + `proveRecoveryPersistence` preserving records
  at a retained location (strict checkpoint busy-row check with non-negative
  frame counts, required connection-file device/inode binding +
  `SQLITE_FCNTL_HAS_MOVED` — unsupported/error fails closed while open stays
  readable — with before/after checkpoint/sync rechecks plus descriptor-bound
  file syncs and a relative `openat` parent-directory binding, deterministic
  actual same-path replacement with a different valid fixture including
  reopen-valid and a pre-replacement checkpointed copy asserting the original
  stays readable, replacement-then-restore rejection (original moved aside,
  replacement flushed at the same path, original restored before return),
  injected checkpoint mutation via live-checkpoint-first-then-replace
  (identity rejection; disk I/O error during the checkpoint itself already
  fails closed) and sync-mutation rejection with retained-copy preservation
  and reopen-valid replacement proof that each fault fired, non-WAL
  checkpoint frame-count refusal, journal-sync seam failure) + transfer
  round-trip.

Engine boundary faults: `Tests/NikoMusicCoreTests/LocalVaultDurabilityFaultTests.swift`
(fresh barrier re-run, capabilities honesty, journal fail-closed including
journal save/write failures, legacy corrupt/mutation, survivor fresh reproof
plus final binding plus journal proof (missing/corrupt/unproven/fresh-throw/
journal-throw all preserve), online-only retirement without materializing,
cancellation during fresh barrier, intermediate-phase restart without
auto-delete, concurrent claim single-owner, admission postponement plus
deterministic mid-copy POSIX ENOSPC plus flush-seam ENOSPC, destination
disappears after copy/barrier and before removal, live temp syscall
acceptance).

Covered elsewhere (not re-proven here, do not claim as new proof):

- interrupted/relaunch recovery: `LocalVaultTransferEngineTests`
  (`recoverAtLaunch` with fresh survivor reproof per project, causal
  supersession without replayed copies or deletions, legacy
  destructive-origin normalization, `recoverInterruptedRemoval` paths);
- provider unavailable/unsynced/slow-sync: `FailingDurabilityProvider`,
  `PromotionDurabilityProvider`, `FinalDurabilityMutatingProvider`
  (post-barrier mutation never publishes a verified generation);
- corrupt archives and unsafe preservation paths: explicit recovery
  rejection tests; capacity postponements (`insufficientSpace` paths,
  including POSIX ENOSPC mapped to `insufficientSpace` for copy and flush
  failures).

Gaps (honest, external only): real hardware power-cut survival, exFAT
flush-contract qualification against primary vendor evidence, and physical
disconnect of a real drive under load. Feasible deterministic faults —
mid-copy ENOSPC, flush-seam ENOSPC, destination disappearance, journal
save/proof failures, survivor fresh reproof with final binding and journal
proof, online-only proof without materializing — are implemented and gated,
not listed as gaps.

## Engine destructive-admission barriers (implemented)

1. **Re-barrier before destructive admission.** `removeActiveCopy`
   (`LocalVaultTransferEngine.swift`) reloads the terminal record, verifies
   manifest bytes, then re-runs `provider.waitUntilDurable` over the exact
   destination generation. Historical `.verifiedLocal` alone never authorizes
   deletion: legacy generations may carry `.verifiedLocal` from
   copy-completion alone, so the old persisted value is discarded and only
   the fresh barrier result is persisted. Capabilities are revalidated
   honestly (`waitsForDurability` must match the fresh claim: local requires
   `.verifiedLocal`, cloud requires `.syncedToProvider`; `.independentlyBackedUp`
   never authorizes here and remote backup is never inferred from filesystem
   presence). After both awaits, containment plus exact manifest bytes are
   revalidated synchronously before persisting any fresh claim. The final
   binding to the exact verified bytes happens after the last
   removal-admission await in `validateRemovalEvidence` (containment, manifest
   at destination, source device+inode binding before/after source manifest
   verification), synchronously before `removeItem` — this avoids an endless
   await race while never trusting a stale claim. Any barrier, capabilities,
   or revalidation throw blocks removal, keeps every copy, and leaves the
   record `archiveVerified`/retryable. Cancellation during the fresh barrier
   or capabilities await propagates as `CancellationError` without
   transitioning to removal, preserving V1 exact-boundary semantics
   (pre-`removeItem` cancellation stays verified/source-retained; at/after
   removal goes `recoveryRequired`).
2. **Prove recovery persistence before destructive admission.** After
   persisting the terminal record with fresh durability and before
   authorizing deletion, the engine calls
   `VaultTransferStoring.proveRecoveryPersistence()` (production SQLite
   delegates to `SQLiteArchiveDatabase.proveRecoveryPersistence()`:
   strict checkpoint plus file/dir syncs with connection-file binding).
   The engine repeats this proof synchronously after the final removal-admission
   await, before the final evidence checks and source removal, with no further
   await between them. A deterministic late-proof failure preserves Active;
   removing only this second proof makes that regression delete the fixture.
   Actual SQLite path replacement also fails closed on the tested host without
   the added proof, so that case does not establish a previously exploitable
   deletion window. A replaced catalog may prevent recording the failure state;
   intact Active and verified archive bytes remain the safety guarantee. On
   throw, destructive admission is blocked, every copy is kept, and read-only
   catalog/recovery access stays available. The default `VaultTransferStoring`
   implementation is fail-closed (`VaultTransferPersistenceProofError.unproven`);
   fixture fakes must opt into explicit deterministic success/failure, and
   production SQLite enforces the real barrier error. `needsLegacyMetadataMigration`
   staging resurrections clear durability (`nil`) and re-enter the normal
   barrier/promotion path, so they cannot inherit a stale proof.
3. **Survivor retirement safety.** `freshSurvivorDurabilityForRetirement` plus
   `survivorRetirementBindingHolds` never delete, never replay a copy, and
   never materialize. Each survivor that could retire an older record must
   freshly re-prove provider durability over its exact destination
   generation (`waitUntilDurable`), with honest capabilities
   (`waitsForDurability == false` with fresh `.verifiedLocal` for local;
   `waitsForDurability == true` with fresh `.syncedToProvider` for cloud;
   `.independentlyBackedUp` never authorizes). After the last await, the
   engine synchronously revalidates the persisted survivor identity, the
   generation-leaf path binding, the content envelope, and — for locally
   held generations — existence plus exact manifest bytes; online-only stays
   byte-neutral (envelope plus path; locality already proven fresh). Then
   `proveRecoveryPersistence()` must succeed before any older record for
   that project is marked `superseded`. Missing, corrupt, unproven (`nil`),
   fresh-barrier-throw, binding-mismatch, or journal-throw all leave older
   records recoverable with staging preserved. No `COPY` is replayed (gated
   by zero write-admission assertions on the retirement path) and no
   replayed deletion occurs. Cloud online-only requires fresh
   `.syncedToProvider` plus live locality (`.fullyLocalCurrent` or
   `.materializationRequired`) without any `materialize` call, so placeholder
   presence alone never retires.
4. **Catalog perf numbers:** capture before/after transfer-path timings when
   touching the SQLite pragma set (still open; no numbers asserted here).

Focused faults: `Tests/NikoMusicCoreTests/LocalVaultDurabilityFaultTests.swift`
(fresh barrier re-run + capabilities mismatch, journal fail-closed including
SQLite seam failure, journal save/write failures, and default fail-closed,
corrupt/mutated legacy generation, survivor fresh reproof with final binding
and journal proof including missing/corrupt/unproven/fresh-throw/
journal-throw preservation plus online-only no-materialize proof,
destination disappears after copy/barrier and before removal, cancellation
during fresh barrier, restart from intermediate phases without auto-delete,
concurrent claim single-owner, admission postponement plus mid-copy POSIX
ENOSPC plus flush-seam ENOSPC, live temp `waitUntilDurable` syscall
acceptance separate from simulated faults). `LocalVaultTransferEngineTests`
pins causal supersession with fresh reproof (no zero-barrier-call
assertions; instead no replayed `COPY`/no deletion) and V1 post-removal
cancellation classification (`removingActiveCopy`/`evictingProviderCache`
stay `recoveryRequired`).

Gaps (honest, external only): real hardware power-cut survival, exFAT
flush-contract qualification against primary vendor evidence, and physical
disconnect of a real drive under load. No power-cut claim anywhere.

## Primary sources

- XNU `fcntl(2)` (F_FULLFSYNC drains the device queue; earlier-synced data on
  that device persists on success; documented for APFS/HFS/FAT/UDF; some
  drives may ignore requests; F_BARRIERFSYNC orders but does not complete):
  https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2
- XNU `fsync(2)` (drive buffering may remain; EIO/EINTR/EINVAL):
  https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fsync.2
- Reducing disk writes (strong persistence cost, best-effort hardware
  contract): https://developer.apple.com/documentation/xcode/reducing-disk-writes
- SQLite `synchronous` (FULL in WAL syncs after each commit; NORMAL can lose
  committed transactions on power/system failure) and `fullfsync` (off by
  default; covers checkpoint syncs; query values back):
  https://www.sqlite.org/pragma.html#pragma_synchronous and
  https://www.sqlite.org/pragma.html#pragma_fullfsync
- SQLite `sqlite3_db_filename` (which file a connection opened) and
  `sqlite3_file_control` with `SQLITE_FCNTL_HAS_MOVED` (VFS moved report,
  enforced only when supported; unsupported is not proof):
  https://www.sqlite.org/c3ref/db_filename.html and
  https://www.sqlite.org/c3ref/file_control.html
