# Restoring linked historical archives

Linked archive cards offer **Get Local & Open**. This downloads online-only files
through the archive provider, verifies a copy in Active Projects, and opens the
newest supported project in its DAW. After restoring, other project versions can
be opened from the Versions list. The original archive remains intact.

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
