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
- exact-commit approved Mac UAT from frozen bytes (`frozen-uat.json` in the private
  run dir, frozen BEFORE validation with its sha256 captured, re-checked after
  validation and at approval with `cmp` frozen-vs-final; validated with
  `--commit COMMIT --expected-build-id VERSION+short12
  --expected-signing-identity NMH_DEVELOPER_ID_APPLICATION`; the same frozen bytes
  back the approval's UAT hash and both final approval validations; never reuse
  test or historical human UAT)
- immutable approval data tying every gate to the artifact and evidence hashes
- update feed generation, and both the enclosure and feed EdDSA signatures verified against the public key embedded in the candidate bundle
- pinned-source provenance: `snapshot-provenance.json` (copied into `dist/release/`)
  records the pinned commit, git metadata, and canonical file hashes; the snapshot
  is a detached worktree (`git worktree add --detach`, genuine `.git`, never
  `git archive`) living in `<release-dir>.provenance-<short12>-<pid>/pinned-source` outside
  `dist/release` with an isolated `.build` and private snapshot dist
  (`<snapshot>/dist/release-build` staged into `dist/release/build`), so
  `rm -rf dist/release` cannot remove it; post-pin preflight reads pinned
  snapshot files/HEAD while shared-ref origin checks are retained
- production Sparkle continuity: the app/feed key equals the repository
  `SPARKLE_PUBLIC_ED_KEY` from the pinned commit; `NMH_SPARKLE_PUBLIC_ED_KEY(_FILE)`
  alternates and resolved-vs-pinned mismatches reject before build/publish
- no source/config override drift: public `VERSION`/`BUNDLE_ID`/Package/arch/key/`NMH_RELEASE_TEST_MODE` envs
  reject before pinning (local-only keeps explicit test use; public always runs
  the pinned Swift build, never the test stub)
- exact 12-gate / 4-override contract from `script/lib/release_gates.sh` with no
  contradictory list; final validator semantic/hash checks authoritative

## Provenance Checks

After a dry-run or local-only build, confirm the pinned-source record survived
output handling and binds the reported commit:

```bash
cat dist/release/snapshot-provenance.json
# pinned_commit must equal the Commit in dist/release/*-release-report.md
```

Behavioral regression (disposable fixture, stubbed side effects, live-source and
original-UAT mutation between stages) runs without signing/publication:

```bash
python3 -m unittest discover -s Tests -p 'test_release_pipeline_provenance.py'
python3 Tests/test_release_provenance.py
bash Tests/test_release_scripts.sh
```

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
