# Release Validation

Run these from a clean checkout on the release machine.

## Preflight

```bash
git status --short --branch
cat VERSION
./script/release-version-verify.sh
./script/public-tree-hygiene.sh
./script/ci.sh
./script/e2e_user_smoke.sh
```

For a version bump, also run:

```bash
NMH_PREVIOUS_VERSION=<old-version> ./script/release-version-verify.sh
```

## Public Artifact

```bash
./script/release-all.sh --public --dry-run-publish
```

This validates:

- app bundle layout and metadata
- Developer ID signing
- hardened runtime, accepting either `Runtime Version` or runtime flags in `codesign`
- app notarization and stapling
- DMG creation after app finalization
- DMG signing, notarization, stapling, and Gatekeeper assessment
- checksum generation after finalization
- basename-only checksum verification
- manifest provenance

## Hosted Artifact Truth

Publishing mode uploads to GitHub Releases, downloads the hosted assets into `dist/release/hosted-download`, and re-runs artifact validation there:

```bash
./script/release-all.sh --public --publish
```

Confirm the release has exactly the expected assets:

```bash
gh release view "v$(cat VERSION)" --json tagName,targetCommitish,assets,url,publishedAt
```

## Installed Truth

After installing from the DMG:

```bash
./script/verify-installed-release.sh /Applications/NikoMusicHub.app
```

The installed bundle must report `CFBundleShortVersionString` from `VERSION` and an `NMHBuildID` beginning with that version plus the source commit.

## Rollback

If a hosted artifact fails validation:

1. Delete or mark the GitHub Release as prerelease/draft.
2. Remove bad assets.
3. Do not move the release tag unless the bad tag has not been consumed; otherwise bump `VERSION`.
4. Rebuild from the intended commit and re-run the full validation path.
5. Document the failed asset hashes and replacement hashes in the release report.
