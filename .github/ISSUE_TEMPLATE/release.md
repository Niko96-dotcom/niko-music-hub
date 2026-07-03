---
name: Release checklist
about: Track a Niko Music Hub release
title: "Release vX.Y.Z"
labels: release
assignees: ""
---

## Identity

- Version:
- Tag:
- Commit:
- Release mode: public / dry-run

## Gates

- [ ] `./script/release-version-verify.sh`
- [ ] `NMH_PREVIOUS_VERSION=<old-version> ./script/release-version-verify.sh`
- [ ] `./script/public-tree-hygiene.sh`
- [ ] `./script/ci.sh`
- [ ] `./script/e2e_user_smoke.sh`
- [ ] `tests/test_release_scripts.sh`
- [ ] `./script/release-all.sh --public --dry-run-publish`
- [ ] `./script/release-all.sh --public --publish`
- [ ] Hosted artifacts downloaded and revalidated
- [ ] Installed `/Applications/NikoMusicHub.app` verified

## Caveats

- Hardware checks skipped:
- Destructive install/upgrade/uninstall checks skipped:
- Credential-gated checks skipped:
- Residual risk:
