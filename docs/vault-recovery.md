# Project Vault recovery copies

A recovery copy is a bounded METADATA backup: the library catalog (archive
index, song metadata, transfer history) plus app settings, exported through
**Settings → Project Vault → Recovery copy**. It is always available, even
when Project Vault is disabled. It is explicitly NOT a backup of your music:
Vault generations, Active Projects folders, DAWs, plug-ins, licenses, and
external sample libraries are never collected into it. How archiving treats
the Active copy and how restores behave is described in
[Vault durability](vault-durability.md).

## What a recovery copy holds

- A consistent snapshot of `archive-index.sqlite` taken through an online
  database backup (index, song metadata, full transfer/catalog records),
  normalized to a standalone file.
- The current app settings, with automation forced off and paused on import
  (`isEnabled=false`, `automaticArchiving=false`,
  `automationEmergencyStop=true`). Root UUIDs, paths, and Keep Local marks are
  preserved.
- A manifest recording the bundle version and file checksums. Import
  validates the manifest, checksums, settings schema, and database integrity
  before writing anything; a copy that does not verify is refused and its
  originals are left untouched.

## What it never does

- Never collects Vault file content, Active Projects, plug-ins, samples, or
  licenses. Back those up separately (see below).
- Never modifies the current library or database on import; it stages a NEW
  isolated library and never overwrites an occupied directory.
- Never deletes anything: failed exports/imports remove only files the
  operation itself staged, and a damaged original is kept for manual DAW
  recovery.
- Never exposes internals in normal copy: verification failures report that
  the copy did not verify, not checksums.

## Step-by-step: export

1. In **Settings → Project Vault**, use **Export recovery metadata** and
   choose where to save the recovery folder.
2. Export holds the Vault mutation lock while it snapshots settings and the
   full database, so no Vault mutation can interleave. The two captures are
   each point-in-time consistent but not a joint transaction; unrelated
   setting writes are never folded in.
3. Separately back up the Vault contents: the complete song folders and the
   Vault generations, plus the Hub catalog and settings. With Music Hub quit,
   copy the application-support folder and settings together; a live SQLite
   copy is not consistent on its own.
4. In Cubase, use **File → Backup Project** for self-contained song folders;
   in Ableton Live, use **File → Collect All and Save** so externally
   referenced samples land inside the project folder. Vault copies and
   verifies the song folder as-is; it does not rewrite sets or gather
   external dependencies. Third-party plug-ins and their licenses must be
   installed separately on any Mac.

The independent-backup checkbox in Project Vault settings records your
confirmation only; Music Hub does not create or verify that backup for you.

## Step-by-step: open a recovered library

1. In **Settings → Project Vault → Recovery copy**, use **Open recovered
   library** and choose the exported recovery folder (directory chooser).
2. Music Hub validates the copy, then stages a NEW isolated library with its
   own settings and `archive-index.sqlite`. The current library is untouched.
3. The recovered library launches as a separate app instance with automation
   disabled and paused. This is an explicit separate library, not a silent
   replacement of your primary library. Nothing launches until you click and
   the import succeeds.
4. Safest activation, in order: verify Active Projects and Archive / Vault
   roots are the correct folders; keep background scheduling off; choose Keep
   a verified copy first if the archiving intent needs changing; only unpause
   when ready to resume work. Roots, identities, and Keep Local marks are
   preserved on import, so unchanged same-Mac roots need no repick — verify
   only. Re-point paths and re-grant folder access only when folders moved or
   on a different Mac (bookmarks do not survive that move). Then run **Test
   Restore** (a disposable rehearsal) before restoring any real song. Verify,
   then restore.
5. Keep the damaged original application-support folder and the recovery
   folder. Without the catalog, existing generation folders alone do not
   reconstruct verified Vault history: missing backup catalogs cannot be
   magically rebuilt. Preserved generations remain available for manual DAW
   recovery; nothing is deleted for you.

## Boundaries

- Same-Mac recovery observed so far: fixture recovery plus UI export/import.
  Replacement-Mac recovery is unproven. A replacement Mac additionally needs
  the DAWs, plug-ins and licenses, external sample libraries, and newly
  granted folder access; a same-Mac rehearsal does not prove that path.
- A disabled Vault keeps its configured Active and Vault roots off the board
  until re-enabled. A paused restore stays paused until explicitly unpaused.
- A corrupt archive, unsafe path, closed-DAW violation, or missing folder
  access stops recovery safely and retains existing copies.
