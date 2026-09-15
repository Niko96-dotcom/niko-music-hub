# Restoring linked historical archives

Archived cards offer **Get Local & Open**. A dialog lists CPR and ALS versions,
including their relative paths and modification dates, and shows the destination
inside Active Projects. Choose a version or keep **Newest available version**.
The complete project folder is restored, including audio and other versions.
Online-only files are downloaded through the archive provider, the local copy is
verified, and the chosen project opens in its DAW. The original archive remains intact.

If the destination already exists, choose a different folder name in the dialog.
The engine checks again before writing, so a folder created after the dialog
opened is also protected. Cancel closes the dialog without starting a restore.
Version listing uses stored manifest metadata or a metadata-only linked inventory;
it does not download file content. If no versions can be listed, make the archive
available locally and retry.

The operation retains the catalog project ID, title, workflow state, identity
evidence and activity timestamp. It uses the historical Active relative path when
available, including significant trailing spaces. An occupied destination is not
overwritten.

## Verification and recovery

- Revalidate the configured roots and the unique catalog location claim.
- Enumerate file names, sizes and modification times without reading file content.
  This transient inventory is download input, not verified content evidence.
- Admit provider downloads against the free-space reserve. Require fully local
  files, match project identity, then hash the whole archive into a new manifest.
  Reject a file-list, size or modification-time change during preparation.
- Persist a restore record with its linked location and immutable content manifest.
  Do not synthesize a historical archive transfer or change previous verification dates.
- Use the existing staging, verification, promotion and DAW-open restore phases.
  Recheck the catalog link on retries and before copy side effects.

A download failure before the content manifest is established leaves the archive
in place; selecting Get Local & Open again restarts preparation. Once a restore
record exists, the existing recovery and Retry Get Local flow resumes that record.
The explicitly selected relative project path is saved in the restore record,
so interruption recovery and Retry Open use the same version. Older records and
the default newest-version choice retain their existing behavior. A missing or
invalid explicit selection stops safely instead of opening another version.
A changed source, revoked link or occupied destination stops the operation safely.

Tests use local fixtures and a simulated materializing provider. Real Dropbox
availability and DAW prompts remain host-dependent acceptance checks.

## Availability, progress and recovery actions

Board and list cards distinguish local archives, online-only archives and downloads.
During an operation they show the observed restore stage. The detail panel also
shows the total file count and size when known. These totals describe the project;
they are not a completion percentage. Progress reads persisted restore phases and
the current download preparation state without rescanning the archive tree.

A stopped restore shows guidance for its stage: provider connection, copying,
verification, destination placement, library persistence or DAW opening. A failed
DAW launch offers **Retry Open** on the restored Active card; retry verifies that
copy again before opening. Integrity or identity failures remain review-only.
