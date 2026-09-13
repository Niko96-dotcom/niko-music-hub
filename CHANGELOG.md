# Changelog

## 1.5.1 - 2026-09-13

- Show "now" instead of "in 0 s" for a download or recording that was just added to the Output Inbox.
- Clean up leftover temporary files next to the Output Inbox index that an interrupted save could leave behind.
- Stop test and review runs from leaving empty preference files behind.
- Harden the release pipeline: refuse to start on a locked screen or without a reachable notary service, retry notary uploads, check secure timestamps on every nested component before upload, and allow a full release rehearsal before the version tag exists.
- Make the incremental archive-rescan tests deterministic instead of timing-based.

## 1.5.0 - 2026-09-11

- Update Niko Music Hub from inside the app: a daily automatic check, Check for Updates… in the app menu, and an Updates section in Settings. Downloads come from a signed release feed and are verified before anything is installed.
- Replace the per-row, detail, and board transports with one persistent preview player that keeps playing while you switch tools or songs.
- Add play buttons to song rows and board cards, and a Previews tab in song detail for choosing the main preview and comparing mixdowns at the same elapsed moment.
- Pause previews automatically while the Recorder captures system audio, so a preview can never end up inside a recording.
- Reorganise song detail around a main-project card, Versions / Previews / Song info / Plugins tabs, and a details rail; Project Vault moves to a sheet unless it needs attention.
- Let empty board stages collapse to a compact rail, narrow the song list, and alternate list and detail below the split-view width.
- Quiet the tool chrome: palette-derived hover fills that work in the light appearance, plain tool titles, a leaner converter intake, and ½ / 1× / 2× tempo chips.
- Generate and verify the update feed as part of every public release, checking both signatures against the key embedded in the shipped app.
- Remove the retired waveform peak loader, transport bar, and metadata chip row, and keep the release-notes check current across version bumps.
- Fix "Convert preview" doing nothing once the WAV Converter had already been opened in the same session; the handoff now queues the file every time.

## 1.4.3 - 2026-09-10

- Add Ableton project support alongside Cubase.
- Preserve Project Vault Keep Local choices when changing settings and retain metadata for archived projects.
- Queue Project Vault operations so archiving and restoring several songs runs in order instead of competing.
- Make Archive Now remove verified Active copies, keep backups separate, and bind archive actions to each song's own folder.
- Explain failed restores, allow safe retries after repairing a backup, and keep backup acknowledgements visible and revocable.
- Guard Vault source removal more carefully by honoring open-file checks before deleting and keeping safe refusals retryable.
- Fix Vault recovery scheduling that could block manual archiving, and wake persisted recovery at its due date.
- Improve Dropbox archive verification and prevent opening projects that contain no project file.
- Improve YouTube download compatibility and recovery from temporary HTTP 403 errors.
- Name demo cards from the delivered artist and title, and rank complete, current bounces ahead of older ones while preserving manual picks.
- Improve archive browsing with clearer board hierarchy, better song row selection, and faster loading.
- Remove unused interface code and redundant wrappers, and strengthen behavioral coverage of backup and restore workflows.

## 1.4.2 - 2026-08-01

- Clean stale project metadata and close the release-preparation debt carried forward from 1.4.1.
- Harden public artifact provenance with an explicit arm64/macOS 14.2 platform contract, exact artifact size, signing, and manifest validation.
- Preserve fail-closed local release engineering across local-only and public workflows, including exact-commit checks and hosted-artifact verification.

## 1.4.1 - 2026-07-22

- Harden Project Vault Done-trigger archiving, Keep Local restore behavior, canonical path matching, and Cubase activity detection.
- Add an end-to-end Friends workflow covering archive, verified restore, Keep Local, and relaunch recovery.
- Show the exact build ID and source commit in the app so an installed build can be identified independently of its marketing version.
- Preserve fail-closed local release engineering and exact installed-build verification for the 1.4.1 delivery.

## 1.4.0 - 2026-07-13

- Establish fail-closed local release engineering for signed/notarized macOS DMG releases.
- Add release version verification, public tree hygiene, artifact validation, checksums, manifests, and installed bundle verification.
