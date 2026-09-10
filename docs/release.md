# Release Engineering

Niko Music Hub is a native macOS Swift Package app. The public artifact contract is a DMG containing `NikoMusicHub.app`.

`VERSION` is the canonical release version source. `BUNDLE_ID` is the permanent app identity source and currently contains `com.niko96.NikoMusicHub`. Bundle metadata, artifact names, release manifests, checksums, release notes, and docs must derive from those files.

The supported release platform is Apple silicon (`arm64`) on macOS 14.2 or newer. `RELEASE_ARCHITECTURES` is the canonical architecture contract; the release host, mounted DMG executable, installed executable, and manifest must all agree. This project does not claim an Intel or universal binary until that contract is deliberately changed and revalidated.

## Distribution

- Channel: GitHub Releases.
- Public artifact: `NikoMusicHub-<version>.dmg`.
- Checksum: `NikoMusicHub-<version>.dmg.sha256`, with a basename-only entry.
- Manifest: `NikoMusicHub-<version>-manifest.json`.
- Manifest provenance: exact commit/build ID, artifact size/hash, supported architecture list, minimum macOS version, and signing/notarization attestation.
- Approval record: `NikoMusicHub-<version>-release-approval.json`.
- Release notes: only the dated current-version section extracted from `CHANGELOG.md`.
- Update feed: `appcast.xml`, the Sparkle feed served to installed builds from `releases/latest/download/appcast.xml`. The basename is fixed by that URL. See `docs/update-feed.md`.
- Install smoke: mount the candidate DMG, copy its app to an isolated release-directory location, then verify the exact build ID, release configuration, source commit, and executable SHA-256. It never trusts an unrelated `/Applications` copy.

## Prerequisites

- macOS 14.2 or newer on Apple silicon (`arm64`).
- Xcode with Swift 6.x.
- A completely clean Git working tree, including untracked files, for every `release-all.sh` artifact. Use `./script/dev.sh run` for dirty local development builds.
- Developer ID Application certificate in the keychain for public releases.
- Notary profile created with `xcrun notarytool store-credentials`.
- EdDSA update signing key in the login keychain, with its public half committed to `SPARKLE_PUBLIC_ED_KEY`. Public mode fails without it, because a release that cannot be described in the feed strands every installed build.
- GitHub CLI authenticated for `--publish`.

Required environment for public mode:

```bash
export NMH_DEVELOPER_ID_APPLICATION="Developer ID Application: ..."
export NMH_NOTARY_PROFILE="niko-music-hub-notary"
export NMH_RELEASE_UAT_EVIDENCE="/absolute/path/to/NikoMusicHub-$(cat VERSION)-uat.json"
```

## Commands

Credential-free local artifact validation (from a clean checkout):

```bash
./script/release-all.sh --local-only
```

Public release validation without upload:

```bash
./script/release-all.sh --public --dry-run-publish
```

Public GitHub release:

```bash
git tag "v$(cat VERSION)"
git push origin "v$(cat VERSION)"
./script/release-all.sh --public --publish --install-smoke
```

Public mode generates and validates `appcast.xml` after the DMG is signed, notarized and stapled, so the enclosure signature covers the exact published bytes. Both the enclosure signature and the feed signature are re-verified against the `SUPublicEDKey` embedded in the candidate bundle: a feed signed by a key the app does not trust fails the release instead of silently disabling updates for every user. Publishing uploads a complete six-asset set and re-validates the hosted feed after download.

`release-all.sh` fails if the tree has any tracked or untracked changes: an artifact must never claim an exact source commit for uncommitted code. Public mode additionally fails if signing/notary credentials or approved UAT evidence are missing, the exact version tag does not resolve to `HEAD` both locally and on `origin`, an identity differs from `BUNDLE_ID`, or any gate fails. Publishing creates one new Release with its complete six-asset set; it refuses pre-existing releases and never overwrites assets. Local-only artifacts are ad-hoc signed, unnotarized, labeled `LOCAL-ONLY-UNSIGNED`, and cannot publish.

Copy `docs/release-uat-evidence.template.json` outside the repository and fill it only after testing the exact commit. The validator requires clean install, upgrade/settings retention, uninstall, launch-at-login, privacy permissions, real recorder audio, live downloader, archive read-only behavior, output handoffs, and user-style E2E to be passed and approved. Historical UAT does not satisfy a new commit.

Public `--skip-tests` is rejected. A release owner can use `--emergency-skip-tests --reason "..."` only as a conspicuous, recorded override; the approval JSON preserves the reason and every overridden gate.

## Version Bump

1. Edit `VERSION`.
2. Update `CHANGELOG.md`.
3. Run `NMH_PREVIOUS_VERSION=<old-version> ./script/release-version-verify.sh`.
4. Run `./script/ci.sh` and `./script/e2e_user_smoke.sh`.

## Credentials

Do not put credentials in scripts, docs, commits, release notes, or shell transcripts. Use keychain profiles, environment variables, or GitHub secrets. Never commit `.env`, `.p12`, `.pfx`, `.pem`, private keys, notary logs with credentials, build output, or local run logs.

## Known Caveats

- GitHub Actions are not required for this repo; local gates are the truth.
- Recorder hardware permission tests are intentionally skipped by `script/ci.sh` and must be checked manually on a machine with a usable system-audio capture setup.
- Public mode additionally runs `script/ci-release.sh` and the focused `script/ci-tsan.sh` concurrency gate.
- Public mode runs user E2E with `NMH_STRICT_UI_E2E=1`; missing Accessibility-visible first-run content is a failure, not a skip.
- `--install-smoke` mounts and installs an isolated copy from the candidate DMG, then proves its exact build ID, release configuration, source commit, and executable hash; the consolidated UAT record remains the authoritative clean-install/upgrade/uninstall proof.
- The local post-publish checks cannot prevent a later privileged tag force-move; protect release tags on the GitHub repository before enabling public publishing.
- App Store review is not part of this release path.
- The update feed URL is permanent. Every installed build polls the URL it shipped with, so `nmh_update_feed_url` cannot be changed without stranding the field.
- Local-only mode skips feed generation when no `SPARKLE_PUBLIC_ED_KEY` is configured; it does not skip it when a key is present and generation fails.
