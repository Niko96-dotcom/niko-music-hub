# Release Checklist

- [ ] Git status is clean or release branch state is documented.
- [ ] `VERSION` was bumped once.
- [ ] `NMH_PREVIOUS_VERSION=<old-version> ./script/release-version-verify.sh` passed.
- [ ] `CHANGELOG.md` matches `VERSION`.
- [ ] `./script/public-tree-hygiene.sh` passed.
- [ ] `./script/ci.sh` passed.
- [ ] `./script/e2e_user_smoke.sh` passed.
- [ ] `tests/test_release_scripts.sh` passed.
- [ ] Public tag `v<VERSION>` points at the intended commit.
- [ ] `./script/release-all.sh --public --dry-run-publish` passed.
- [ ] Checksums were generated after notarization/stapling.
- [ ] DMG layout contains `NikoMusicHub.app`.
- [ ] `./script/release-all.sh --public --publish` uploaded exactly the expected GitHub assets.
- [ ] Hosted assets were downloaded and revalidated.
- [ ] Installed `/Applications/NikoMusicHub.app` matches `VERSION` and `NMHBuildID`.
- [ ] Skipped hardware, credential-gated, destructive install, or App Store checks are named in the release report.
