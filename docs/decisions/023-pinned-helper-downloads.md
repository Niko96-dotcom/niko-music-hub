# Decision: Set Up installs pinned helper builds and a signed yt-dlp

**Status:** Accepted — implemented (`HelperToolPins`, `YtDlpSigningKey`, `script/update-helper-pins.py`;
`HelperToolPinsTests`, `YtDlpSigningKeyTests`, `HelperToolPinsSourceTests`)  
**Date:** 2026-10-27  
**Deciders:** Niko Music Hub owner (approved the proposal on 2026-10-27) + implementation  
**Scope:** `Sources/AppCore/HelperTools/`, `script/update-helper-pins.py`, the helper installer tests

## Context

Set Up's one-click install (`HelperToolInstaller`) downloaded every helper through a moving link and
checked it against a checksum from the same place:

| Helper | Link | Checksum |
|---|---|---|
| yt-dlp | GitHub `releases/latest` | `SHA2-256SUMS` from the same release |
| FFmpeg, ffprobe | ffmpeg.martin-riedl.de `redirect/latest` | `.sha256` from the same host |
| uv | GitHub `releases/latest` | `.sha256` from the same release |
| demucs-mlx | `uv tool install --upgrade demucs-mlx[convert]` | none |

A build that changed on a host passed its check, and two installs on two days could get different
tools. demucs-mlx showed the cost: the `convert` extra (PyTorch and Demucs, about 1 GB) was added on
2026-09-23, when demucs-mlx 1.4.13 converted the PyTorch weights itself. From 1.6.0 (2026-10-05) it
downloads ready MLX weights from Hugging Face, accepts them only with the SHA-256 built into the package,
and never needs PyTorch. The way the model arrived changed upstream while the app did not change.

What the hosts publish (checked on 2026-10-27):

- **yt-dlp:** each release has `SHA2-256SUMS.sig`, an OpenPGP v4 signature (RSA 4096, SHA-512) by
  "Simon Sawicki (yt-dlp signing key)", fingerprint `AC0C BBE6 848D 6A87 3464 AF4E 57CF 6593 3B5A 7581`,
  unchanged since 2023-02-26. The key is `public.key` in the yt-dlp repository.
- **FFmpeg:** fixed per-build links (`/download/macos/arm64/<build>/ffmpeg.zip`) with `.sha256` files and
  no separate signature. Release builds back to 5.0 (2022-01-15) still download. The binaries carry the
  Developer ID signature of Martin Riedl (team `KU3N25YGLU`) with the hardened runtime.
- **uv:** fixed release links with `.sha256` files, about ten releases a month.
- **demucs-mlx:** PyPI; eight releases between 2026-09-23 and 2026-10-05.

## Decision

1. `HelperToolPins` is what an install trusts, passed to the installer as a value. `HelperToolPins.release`
   (`HelperToolPins.swift`) holds the shipped values; tests pass their own.
2. FFmpeg, ffprobe and uv install only the exact build in the pins, checked against the SHA-256 there.
   The installer fetches no checksum from their hosts and no longer checks the FFmpeg host name: the hash
   covers it.
3. demucs-mlx installs into a fresh virtual environment per attempt with
   `uv pip install --require-hashes --no-build -r <lock>`. The lock in the pins names demucs-mlx and
   every package it needs, one version and the file hashes each, and leaves out the `convert` extra. The
   model weights are pinned through demucs-mlx's own hashes. The installer's home folder is injected, so
   the live test can start with an empty model cache.
4. yt-dlp keeps following the newest release, because sites change and old builds stop working. The
   installer asks GitHub's API for the newest tag and refuses a tag that is no release date or is older
   than `YtDlpVersionPolicy.youtubeCompatibilityFloor` (an old release is still validly signed, so the date
   stops a downgrade). It downloads that tag's `SHA2-256SUMS`, its signature and the binary;
   `YtDlpSigningKey` verifies the signature with the key in the pins (Security framework, RSA PKCS #1 v1.5
   over the OpenPGP v4 hash), and the binary must match the hash in the signed list. A refusal is
   `HelperInstallError.untrustedRelease`, which tells the person to update the app if it repeats.
5. `script/update-helper-pins.py` makes a new pin: it finds the newest builds (or the ones named), checks
   each against the host's SHA-256 file, the FFmpeg Developer ID team and the tool's version output,
   locks demucs-mlx with the new uv, stops if yt-dlp's published key is not the shipped one, and rewrites
   `HelperToolPins.swift`. The live installer tests and `./script/ci.sh` run before the commit.
6. Enforced by `HelperToolPinsTests` (exact https builds, full hashes, a complete lock without PyTorch),
   `YtDlpSigningKeyTests` (the real 2026.10.26 release verifies; a changed byte, another key, a forged
   issuer and truncated signatures fail), the installer tests, and `HelperToolPinsSourceTests` (no
   moving `latest` download link under `AppCore/HelperTools/`).

## Options

| Option | Complexity | Pros | Cons |
|---|---|---|---|
| A. Keep the moving links | None | Always the newest tools | A changed build passes; upstream changes reach users unannounced |
| **B. Pin FFmpeg, uv and demucs-mlx; verify yt-dlp by signature** | Medium | Integrity from the app, not the host; yt-dlp stays current | Updates need the script and a new app release; a yt-dlp key change stops installs until an update |
| C. Pin yt-dlp too | Low | Same rule for every helper | A pinned yt-dlp stops working within weeks |
| D. Mirror the builds on the app's own release host | High | Availability does not depend on martin-riedl.de | GPL source duties for the FFmpeg builds; one more host to run |

## Consequences

- An install gets the same FFmpeg, uv and demucs-mlx until the next app release pins new ones.
- A Stem Separation install is about 1 GB instead of about 1.2 GB (no PyTorch). Existing installs keep
  their environment until "Install again", which also removes the old one.
- The pins protect content, not availability: martin-riedl.de is one person's service. A download whose
  connection drops starts again twice (`URLSessionHelperDownloader`, added 2026-10-28); a host that stays
  down still fails the install.
- If yt-dlp changes its key, installs refuse every new release until an app update ships the new key.
  The script stops on such a change, so the change is reviewed by hand.
- Helpers the person chooses or the app finds in system folders are still trusted by their path and
  version only (threat model TM-003).
