# In-App Updates

Niko Music Hub updates itself with [Sparkle](https://sparkle-project.org) 2.9.6, pinned exactly in `Package.swift`. Updates are delivered through the same channel as manual downloads: the DMG attached to a GitHub Release.

## Contract

| Piece | Value |
|---|---|
| Feed URL | `https://github.com/Niko96-dotcom/niko-music-hub/releases/latest/download/appcast.xml` |
| Feed asset name | `appcast.xml` — fixed, because `latest/download/` resolves by basename |
| Enclosure | `NikoMusicHub-<version>.dmg` from the same release |
| Enclosure signature | EdDSA (ed25519), verified before extraction |
| Feed signature | EdDSA over the feed body (`SURequireSignedFeed`) |
| Check schedule | Automatic, every 24h, enabled by default with no first-run prompt |

The feed URL is a one-way door. Every build already installed polls whatever URL it shipped with, forever. `nmh_update_feed_url` in `script/release-env.sh` is the only definition; changing it strands every build in the field.

## Keys

`SPARKLE_PUBLIC_ED_KEY` in the repository root holds the **public** half of the signing key pair. It is embedded into the bundle as `SUPublicEDKey`. The private half lives only in the release owner's login Keychain and is never committed, exported into the repository, or passed on a command line.

Create the pair once:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

That stores the private key in the Keychain and prints the public key. Write the printed public key — and nothing else — into `SPARKLE_PUBLIC_ED_KEY`, then commit that file.

To read the public key back later:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
```

Rotating the key strands every installed build, because those builds only trust the key they shipped with. Treat it as permanent.

## Fail-closed behavior

Nothing about this path degrades quietly into an unverified update:

- No `SPARKLE_PUBLIC_ED_KEY` means the bundle ships with **no** `SUFeedURL` and no `SUPublicEDKey` at all. The app reports that updates are unavailable instead of silently reading as up to date.
- A debug bundle never ships a live feed unless `NMH_UPDATE_FEED_URL` names one explicitly, so `./script/dev.sh run` and `./script/e2e_user_smoke.sh` builds never contact the feed.
- `NIKO_MUSIC_HUB_E2E_SMOKE=1` disables the updater before Sparkle is constructed, so an end-to-end run can never stage an install over the bundle it is testing.
- A public release without a usable key fails rather than publishing an app that can no longer be updated.
- `script/validate-update-feed.py` re-verifies both signatures against the public key read out of the **candidate bundle itself**, so a feed signed by the wrong key fails the release instead of silently breaking every user's update check.
- A non-HTTPS feed URL is refused by both the build script and the app.

## Release integration

`script/release-all.sh` generates the feed after the DMG is signed, notarized and stapled — the enclosure signature covers the exact published bytes — and before the approval record. Publishing uploads six assets: the DMG, its checksum, the manifest, the approval record, the release notes, and `appcast.xml`. The hosted feed is downloaded and re-validated where it landed, alongside the existing byte-equality checks.

Release notes come from the current `CHANGELOG.md` section and are embedded in the feed item as CDATA, so there is no separate release-notes URL to sign and keep in sync.

## Testing an update round trip

Never point a test at the production feed; a test build that finds the real release will try to install it. Use a separate feed and a throwaway key.

```bash
# 1. A throwaway key pair, kept out of the Keychain.
python3 - <<'PY'
import base64, os
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
seed = os.urandom(32)
pub = ed25519.Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(
    encoding=serialization.Encoding.Raw, format=serialization.PublicFormat.Raw)
open("/tmp/nmh-test-private.key", "w").write(base64.b64encode(seed).decode())
print("public:", base64.b64encode(pub).decode())
PY
```

Build an older version pointed at a local test feed, serve the feed and DMG over HTTPS, then publish a newer build into that feed with:

```bash
NMH_SPARKLE_PRIVATE_KEY_FILE=/tmp/nmh-test-private.key \
NMH_UPDATE_FEED_URL=https://<your-test-host>/appcast.xml \
NMH_SPARKLE_PUBLIC_ED_KEY=<printed public key> \
./script/release-all.sh --local-only --skip-tests
```

Sparkle will not accept a plain `http://` feed, and neither will this project's build script. Label any evidence produced this way as test-feed evidence: it does not stand in for a production-feed round trip.

## Known limits

- Sparkle's own window owns the download progress bar. The standard user driver exposes no byte counts, so the in-app status line names the version being downloaded but not a percentage.
- `generate_appcast` reads the private key from the Keychain by default and will prompt for access on first use. `NMH_SPARKLE_KEY_ACCOUNT` selects a non-default Keychain account; `NMH_SPARKLE_PRIVATE_KEY_FILE` is for test feeds only.
- `script/validate-update-feed.py` needs the `cryptography` module for `/usr/bin/python3`. If it is missing the release fails rather than skipping signature verification.
- Feed generation requires resolved SPM artifacts (`swift package resolve`), since `generate_appcast` ships inside the Sparkle package.
