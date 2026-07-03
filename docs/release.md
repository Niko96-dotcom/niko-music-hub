# Release Engineering

Niko Music Hub is a native macOS Swift Package app. The public artifact contract is a DMG containing `NikoMusicHub.app`.

`VERSION` is the only canonical release version source. Bundle metadata, artifact names, release manifests, checksums, release notes, and docs must derive from that file.

## Distribution

- Channel: GitHub Releases.
- Public artifact: `NikoMusicHub-<version>.dmg`.
- Checksum: `NikoMusicHub-<version>.dmg.sha256`, with a basename-only entry.
- Manifest: `NikoMusicHub-<version>-manifest.json`.
- Install path for smoke verification: `/Applications/NikoMusicHub.app`.

## Prerequisites

- macOS 14.2 or newer.
- Xcode with Swift 6.x.
- Developer ID Application certificate in the keychain for public releases.
- Notary profile created with `xcrun notarytool store-credentials`.
- GitHub CLI authenticated for `--publish`.

Required environment for public mode:

```bash
export NMH_DEVELOPER_ID_APPLICATION="Developer ID Application: ..."
export NMH_NOTARY_PROFILE="niko-music-hub-notary"
```

## Commands

Credential-free local artifact dry run:

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
./script/release-all.sh --public --publish --install-smoke
```

Public mode fails if signing/notary credentials are missing, if the tag does not point at `HEAD`, or if validation fails. Local-only artifacts are ad-hoc signed, unnotarized, labeled `LOCAL-ONLY-UNSIGNED`, and cannot publish.

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
- Install smoke writes to `/Applications` and is opt-in via `--install-smoke`.
- App Store review is not part of this release path.
