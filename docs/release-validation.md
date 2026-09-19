# Release Validation

Run these from a clean checkout on the release machine.

## Preflight

```bash
git status --short --branch
cat VERSION
cat BUNDLE_ID
./script/release-preflight.sh
git ls-remote --tags origin "refs/tags/v$(cat VERSION)" "refs/tags/v$(cat VERSION)^{}"
./script/release-version-verify.sh
./script/public-tree-hygiene.sh --public-release
./script/ci.sh
./script/e2e_user_smoke.sh
./script/ci-release.sh
./script/ci-tsan.sh
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
- supported `arm64` architecture and `LSMinimumSystemVersion` derived from the package contract
- Developer ID signing
- hardened runtime, accepting either `Runtime Version` or runtime flags in `codesign`
- secure timestamp, hardened runtime, and the app's own Team ID on every nested Sparkle component, with no entitlements on the helpers
- exactly `com.apple.security.device.audio-input` as the app's entitlement set
- `CFBundleVersion` above the highest `sparkle:version` on the live update feed
- app notarization and stapling
- DMG creation after app finalization
- DMG signing, notarization, stapling, and Gatekeeper assessment
- checksum generation after finalization
- basename-only checksum verification
- manifest provenance
- manifest artifact size, architecture, minimum-macOS, and signing/notarization attestation
- exact `com.niko96.NikoMusicHub` identity in source, bundle, artifact, manifest, and installed app
- exact-commit approved Mac UAT
- immutable approval data tying every gate to the artifact and evidence hashes
- update feed generation, and both the enclosure and feed EdDSA signatures verified against the public key embedded in the candidate bundle

## Hosted Artifact Truth

Publishing mode requires the exact release tag to already exist on `origin`, creates one new Release with its complete asset set, downloads the hosted assets into `dist/release/hosted-download`, byte-compares every hosted asset against its candidate, and re-runs artifact and update-feed validation there:

```bash
./script/release-all.sh --public --publish
```

Confirm the release has exactly the expected assets and that the tag remains bound to the intended commit:

```bash
gh release view "v$(cat VERSION)" --json tagName,targetCommitish,assets,url,publishedAt
git ls-remote --tags origin "refs/tags/v$(cat VERSION)" "refs/tags/v$(cat VERSION)^{}"
```

## Installed Truth

For a separate manual install, after installing from the DMG:

```bash
./script/verify-installed-release.sh /Applications/NikoMusicHub.app
```

The installed bundle must report `CFBundleShortVersionString` from `VERSION`, `CFBundleIdentifier` from `BUNDLE_ID`, and an `NMHBuildID` beginning with that version plus the source commit. `release-all.sh --install-smoke` performs the equivalent check from an isolated copy of the mounted candidate rather than trusting `/Applications`.

## Rollback

If a hosted artifact fails validation:

1. Do not overwrite or replace a published asset set.
2. If the release was never consumed, take it down under the repository's release incident policy; otherwise leave the evidence intact.
3. Do not move the release tag. Bump `VERSION`, rebuild from the intended commit, and publish a new immutable release.
4. Re-run the full validation path, including remote-tag and hosted byte-equality checks.
5. Document the failed artifact hashes and the successor release in the incident record.
