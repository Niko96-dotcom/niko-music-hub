#!/usr/bin/env python3
"""Pin new helper builds for Set Up's one-click install (docs/decisions/023-pinned-helper-downloads.md).

Finds the newest FFmpeg/ffprobe macOS arm64 release build on ffmpeg.martin-riedl.de, the newest uv release and
the newest demucs-mlx on PyPI, or the versions you name. It checks each download against its publisher:
the host's own SHA-256 file, the FFmpeg Developer ID team, each tool's version output. It locks demucs-mlx and
every package it needs with the new uv, checks that yt-dlp still signs with the key in YtDlpSigningKey.swift,
and only then rewrites Sources/AppCore/HelperTools/HelperToolPins.swift. Nothing else changes.

Usage: script/update-helper-pins.py [--ffmpeg BUILD] [--uv VERSION] [--demucs-mlx VERSION]
  BUILD is the build's folder on the host, for example 1789931890_9.0.2.

Then: NMH_LIVE_HELPER_INSTALL=1 NMH_LIVE_HELPER_INSTALL_STEMS=1 swift test --filter HelperToolInstallerLiveTests,
./script/ci.sh, review the diff (and the install sizes in the docs), commit.
"""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PINS = os.path.join(ROOT, "Sources/AppCore/HelperTools/HelperToolPins.swift")
SIGNING_KEY = os.path.join(ROOT, "Sources/AppCore/HelperTools/YtDlpSigningKey.swift")
FFMPEG_HOST = "https://ffmpeg.martin-riedl.de"
FFMPEG_TEAM = "KU3N25YGLU"
UV_ASSET = "uv-aarch64-apple-darwin.tar.gz"
PYTHON = "3.12"
MACOS_TARGET = "14.0"


def fail(message):
    sys.exit(f"update-helper-pins: {message}")


def run(*command, env=None):
    result = subprocess.run(command, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        fail(f"{' '.join(command[:3])} failed: {result.stderr.strip()[-400:]}")
    return result.stdout


def fetch_text(url):
    return run("curl", "-fsSL", url)


def download(url, path):
    run("curl", "-fsSL", "--retry", "3", "-o", path, url)
    return path


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for block in iter(lambda: file.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def checked_download(url, path, expected):
    download(url, path)
    actual = sha256(path)
    if actual != expected:
        fail(f"{url}: SHA-256 {actual} does not match the publisher's {expected}")
    return actual


def newest_ffmpeg_build():
    location = run("curl", "-sS", "-o", "/dev/null", "-w", "%{redirect_url}",
                   f"{FFMPEG_HOST}/redirect/latest/macos/arm64/release/ffmpeg.zip")
    match = re.search(r"/download/macos/arm64/([0-9]+_[^/]+)/ffmpeg\.zip$", location)
    if not match:
        fail(f"no FFmpeg release build behind the latest link ({location!r})")
    return match.group(1)


def pin_ffmpeg(build, work):
    pins = {}
    for name in ("ffmpeg", "ffprobe"):
        url = f"{FFMPEG_HOST}/download/macos/arm64/{build}/{name}.zip"
        published = fetch_text(url + ".sha256").split()[0]
        archive = os.path.join(work, f"{name}.zip")
        pins[name] = (url, checked_download(url, archive, published))
        unpacked = os.path.join(work, f"{name}-unzipped")
        run("ditto", "-x", "-k", archive, unpacked)
        binary = os.path.join(unpacked, name)
        requirement = f'anchor apple generic and certificate leaf[subject.OU] = "{FFMPEG_TEAM}"'
        run("codesign", "--verify", "--strict", f"-R={requirement}", binary)
        print(f"  {name}: {run(binary, '-version').splitlines()[0]}")
    return pins


def pin_uv(version, work):
    url = f"https://github.com/astral-sh/uv/releases/download/{version}/{UV_ASSET}"
    published = fetch_text(url + ".sha256").split()[0]
    archive = os.path.join(work, UV_ASSET)
    digest = checked_download(url, archive, published)
    run("tar", "-xzf", archive, "-C", work)
    uv = os.path.join(work, "uv-aarch64-apple-darwin", "uv")
    print(f"  {run(uv, '--version').strip()}")
    return (url, digest), uv


def lock_demucs(uv, version, work):
    request = os.path.join(work, "demucs-in.txt")
    lock = os.path.join(work, "demucs-lock.txt")
    with open(request, "w") as file:
        file.write(f"demucs-mlx=={version}\n")
    env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET=MACOS_TARGET, UV_NO_CONFIG="1", UV_CACHE_DIR=os.path.join(work, "uv-cache"))
    run(uv, "pip", "compile", request, "--generate-hashes", "--python-version", PYTHON,
        "--python-platform", "aarch64-apple-darwin", "--no-header", "--no-annotate", "-o", lock, env=env)
    text = open(lock).read().rstrip("\n")
    packages = re.findall(r"^([A-Za-z0-9_.-]+)==", text, re.MULTILINE)
    if any(name.lower() in ("torch", "demucs") for name in packages):
        fail(f"the lock pulls in PyTorch: {packages}")
    print(f"  demucs-mlx {version}: {len(packages)} packages ({', '.join(packages)})")
    return text


def ytdlp_fingerprint():
    armored = fetch_text("https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/public.key").splitlines()
    key = base64.b64decode("".join(line for line in armored
                                   if line and not line.startswith(("-----", "=")) and ":" not in line))
    tag = key[0]
    if tag & 0x40:
        length, header = key[1], 2
        if 192 <= length < 224:
            length, header = ((length - 192) << 8) + key[2] + 192, 3
    else:
        header = {0: 2, 1: 3, 2: 5}[tag & 3]
        length = int.from_bytes(key[1:header], "big")
    packet = key[header:header + length]
    return hashlib.sha1(b"\x99" + struct.pack(">H", len(packet)) + packet).hexdigest().upper()


def write_pins(build, ffmpeg, uv_version, uv_pin, demucs_version, lock):
    ffmpeg_version = build.split("_", 1)[1]
    text = f'''import Foundation

// Written by script/update-helper-pins.py (docs/decisions/023-pinned-helper-downloads.md); change it through the
// script. The helper builds this release installs:
// - FFmpeg and ffprobe {ffmpeg_version}: macOS arm64 release build by Martin Riedl, Developer ID team {FFMPEG_TEAM}.
// - uv {uv_version}.
// - demucs-mlx {demucs_version} without the PyTorch `convert` extra, locked with `uv pip compile --generate-hashes
//   --python-version {PYTHON} --python-platform aarch64-apple-darwin` (uv {uv_version}, MACOSX_DEPLOYMENT_TARGET={MACOS_TARGET}).
// Each SHA-256 was checked against the host's own checksum file when the pin was made. yt-dlp has no pin: each
// release must be signed by the yt-dlp signing key (YtDlpSigningKey.swift).
extension HelperToolPins {{
    public static let release = HelperToolPins(
        ffmpeg: PinnedDownload(
            url: URL(string: "{ffmpeg["ffmpeg"][0]}")!,
            sha256: "{ffmpeg["ffmpeg"][1]}"
        ),
        ffprobe: PinnedDownload(
            url: URL(string: "{ffmpeg["ffprobe"][0]}")!,
            sha256: "{ffmpeg["ffprobe"][1]}"
        ),
        uv: PinnedDownload(
            url: URL(string: "{uv_pin[0]}")!,
            sha256: "{uv_pin[1]}"
        ),
        demucsRequirements: demucsLock,
        ytDlpSigningKey: .ytDlpProject
    )

    private static let demucsLock = #"""
{lock}
"""#
}}
'''
    with open(PINS, "w") as file:
        file.write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ffmpeg", help="FFmpeg build folder on the host, for example 1789931890_9.0.2")
    parser.add_argument("--uv", help="uv release, for example 0.13.6")
    parser.add_argument("--demucs-mlx", dest="demucs", help="demucs-mlx version, for example 1.6.1")
    args = parser.parse_args()

    work = tempfile.mkdtemp(prefix="nmh-helper-pins-")
    try:
        build = args.ffmpeg or newest_ffmpeg_build()
        uv_version = args.uv or json.loads(fetch_text("https://api.github.com/repos/astral-sh/uv/releases/latest"))["tag_name"]
        demucs_version = args.demucs or json.loads(fetch_text("https://pypi.org/pypi/demucs-mlx/json"))["info"]["version"]
        print(f"Pinning FFmpeg {build}, uv {uv_version}, demucs-mlx {demucs_version}")

        ffmpeg = pin_ffmpeg(build, work)
        uv_pin, uv = pin_uv(uv_version, work)
        lock = lock_demucs(uv, demucs_version, work)

        shipped = re.search(r'fingerprint: "([0-9A-F]{40})"', open(SIGNING_KEY).read()).group(1)
        published = ytdlp_fingerprint()
        if published != shipped:
            fail(f"yt-dlp now publishes key {published}, the app trusts {shipped}: review the new key, then update "
                 "YtDlpSigningKey.swift by hand (fingerprint and DER) and YtDlpSigningKeyTests' fixture")
        print(f"  yt-dlp signing key unchanged ({shipped})")

        write_pins(build, ffmpeg, uv_version, uv_pin, demucs_version, lock)
        print(f"Wrote {os.path.relpath(PINS, ROOT)}. Next: the live installer tests, ./script/ci.sh, review, commit.")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
