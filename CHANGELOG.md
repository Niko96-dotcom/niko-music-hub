# Changelog

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
