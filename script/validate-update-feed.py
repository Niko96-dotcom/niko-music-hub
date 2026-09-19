#!/usr/bin/env /usr/bin/python3
"""Prove a generated appcast is one the shipped app can actually consume.

The point of this gate is the key match. `sign_update --verify` proves a
signature is valid for whichever key signed it; it cannot prove that the key
baked into the bundle we are about to publish is that same key. A release that
ships an app trusting key A alongside a feed signed by key B looks perfectly
healthy until every user's update check silently fails, so the enclosure and
feed signatures are re-verified here against the public key read out of the
candidate bundle itself.
"""

from __future__ import annotations

import argparse
import base64
import plistlib
import re
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ED25519_PUBLIC_KEY_BYTES = 32
# generate_appcast appends this trailer after the closing </rss>; `length` is the
# byte count of the prefix the signature covers.
FEED_SIGNATURE_PATTERN = re.compile(
    rb"<!--\s*sparkle-signatures:\s*\nedSignature:\s*(\S+)\s*\nlength:\s*(\d+)\s*\n-->\s*\Z"
)


class FeedValidationError(Exception):
    pass


def load_verifier(public_key_base64: str):
    try:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric import ed25519
    except ImportError as error:  # pragma: no cover - environment failure
        raise FeedValidationError(
            "update feed validation requires the 'cryptography' module for "
            f"/usr/bin/python3 and could not import it ({error}). Refusing to "
            "publish an unverified feed."
        ) from error

    try:
        raw = base64.b64decode(public_key_base64, validate=True)
    except Exception as error:
        raise FeedValidationError(f"SUPublicEDKey is not valid base64: {error}") from error
    if len(raw) != ED25519_PUBLIC_KEY_BYTES:
        raise FeedValidationError(
            f"SUPublicEDKey must decode to {ED25519_PUBLIC_KEY_BYTES} bytes, got {len(raw)}"
        )
    key = ed25519.Ed25519PublicKey.from_public_bytes(raw)

    def verify(signature_base64: str, payload: bytes, what: str) -> None:
        try:
            signature = base64.b64decode(signature_base64, validate=True)
        except Exception as error:
            raise FeedValidationError(f"{what} signature is not valid base64: {error}") from error
        try:
            key.verify(signature, payload)
        except InvalidSignature as error:
            raise FeedValidationError(
                f"{what} signature does not verify against the SUPublicEDKey embedded in the "
                "candidate app bundle; the app would reject this update"
            ) from error

    return verify


def read_bundle_update_keys(app: Path) -> dict:
    info_path = app / "Contents" / "Info.plist"
    if not info_path.is_file():
        raise FeedValidationError(f"candidate bundle has no Info.plist: {info_path}")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)

    feed_url = (info.get("SUFeedURL") or "").strip()
    public_key = (info.get("SUPublicEDKey") or "").strip()
    if not feed_url:
        raise FeedValidationError("candidate bundle has no SUFeedURL; it cannot receive updates")
    if not feed_url.startswith("https://"):
        raise FeedValidationError(f"candidate bundle SUFeedURL is not HTTPS: {feed_url}")
    if not public_key:
        raise FeedValidationError("candidate bundle has no SUPublicEDKey; updates would be unverified")
    bundle_short_version = (info.get("CFBundleShortVersionString") or "").strip()
    bundle_version = (info.get("CFBundleVersion") or "").strip()
    if not bundle_short_version:
        raise FeedValidationError(
            "candidate bundle has no CFBundleShortVersionString; the feed cannot prove the update matches the shipped version"
        )
    if not bundle_version:
        raise FeedValidationError(
            "candidate bundle has no CFBundleVersion; the feed cannot prove the build number advances"
        )
    return {
        "feed_url": feed_url,
        "public_key": public_key,
        "bundle_short_version": bundle_short_version,
        "bundle_version": bundle_version,
        "require_signed_feed": bool(info.get("SURequireSignedFeed")),
        "verify_before_extraction": bool(info.get("SUVerifyUpdateBeforeExtraction")),
    }


def sparkle_text(item: ElementTree.Element, name: str) -> str | None:
    node = item.find(f"{{{SPARKLE_NS}}}{name}")
    return None if node is None or node.text is None else node.text.strip()


def expect(actual, expected, label: str) -> None:
    if actual != expected:
        raise FeedValidationError(f"appcast {label} is {actual!r}, expected {expected!r}")


def validate(args: argparse.Namespace) -> None:
    appcast_path = Path(args.appcast)
    artifact_path = Path(args.artifact)
    app_path = Path(args.app)

    for path, label in ((appcast_path, "appcast"), (artifact_path, "artifact"), (app_path, "app bundle")):
        if not path.exists():
            raise FeedValidationError(f"missing {label}: {path}")

    bundle = read_bundle_update_keys(app_path)
    verify = load_verifier(bundle["public_key"])

    # SURequireSignedFeed only takes effect when the enclosure is verified before
    # extraction; shipping the first without the second claims a protection the
    # app does not actually apply.
    if bundle["require_signed_feed"] and not bundle["verify_before_extraction"]:
        raise FeedValidationError(
            "candidate bundle sets SURequireSignedFeed without its prerequisite "
            "SUVerifyUpdateBeforeExtraction"
        )

    raw_feed = appcast_path.read_bytes()
    try:
        root = ElementTree.fromstring(raw_feed)
    except ElementTree.ParseError as error:
        raise FeedValidationError(f"appcast is not well-formed XML: {error}") from error

    items = root.findall("./channel/item")
    if len(items) != 1:
        raise FeedValidationError(
            f"appcast must describe exactly one update for this release, found {len(items)}"
        )
    item = items[0]

    expect(bundle["bundle_short_version"], args.version, "candidate bundle CFBundleShortVersionString")
    expect(bundle["bundle_version"], args.build_number, "candidate bundle CFBundleVersion")
    expect(sparkle_text(item, "shortVersionString"), args.version, "sparkle:shortVersionString")
    expect(sparkle_text(item, "version"), args.build_number, "sparkle:version")
    expect(
        sparkle_text(item, "shortVersionString"),
        bundle["bundle_short_version"],
        "sparkle:shortVersionString vs candidate bundle CFBundleShortVersionString",
    )
    expect(
        sparkle_text(item, "version"),
        bundle["bundle_version"],
        "sparkle:version vs candidate bundle CFBundleVersion (a stale bundle build number means installed apps would never be offered this release)",
    )
    expect(sparkle_text(item, "minimumSystemVersion"), args.minimum_macos, "sparkle:minimumSystemVersion")

    # The current product contract is exactly one arm64 architecture. Zero or
    # multiple architectures must fail closed here instead of silently skipping
    # the hardwareRequirements check (the old code validated only when exactly
    # one architecture was requested).
    expected_architectures = args.architectures.split()
    if expected_architectures != ["arm64"]:
        raise FeedValidationError(
            f"release architecture contract is {expected_architectures!r}; feed validation "
            "requires exactly one arm64 architecture and refuses zero, multiple, or "
            "non-arm64 instead of skipping hardwareRequirements validation"
        )
    hardware = sparkle_text(item, "hardwareRequirements")
    expect(hardware, expected_architectures[0], "sparkle:hardwareRequirements")

    description = item.find("description")
    if description is None or not (description.text or "").strip():
        raise FeedValidationError("appcast item has no release notes description")

    # The release contract is exactly one full enclosure. Delta updates (extra
    # enclosures or sparkle:deltaFrom) are not published, so any of them fails
    # closed instead of shipping an update path the validators never proved.
    def _local_name(tag: str) -> str:
        return tag.split("}", 1)[-1] if "}" in tag else tag

    enclosures = [child for child in item if _local_name(child.tag) == "enclosure"]
    if len(enclosures) != 1:
        raise FeedValidationError(
            f"appcast item must carry exactly one full enclosure, found {len(enclosures)}"
        )
    enclosure = enclosures[0]
    if enclosure.tag != "enclosure":
        raise FeedValidationError(
            f"appcast enclosure must be a plain RSS enclosure, found tag {enclosure.tag!r}"
        )
    for key in enclosure.attrib:
        if _local_name(key) == "deltaFrom":
            raise FeedValidationError(
                "appcast enclosure carries sparkle:deltaFrom; delta enclosures are not "
                "part of the release contract"
            )

    expect(enclosure.get("url"), args.expected_enclosure_url, "enclosure url")

    artifact_bytes = artifact_path.read_bytes()
    expect(enclosure.get("length"), str(len(artifact_bytes)), "enclosure length")

    enclosure_signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature")
    if not enclosure_signature:
        raise FeedValidationError("appcast enclosure has no sparkle:edSignature")
    verify(enclosure_signature, artifact_bytes, "enclosure")

    match = FEED_SIGNATURE_PATTERN.search(raw_feed)
    if bundle["require_signed_feed"]:
        if match is None:
            raise FeedValidationError(
                "candidate bundle sets SURequireSignedFeed but the appcast carries no "
                "sparkle-signatures trailer; every update check would be rejected"
            )
        signed_length = int(match.group(2))
        if signed_length > len(raw_feed):
            raise FeedValidationError(
                f"appcast signature covers {signed_length} bytes but the file is {len(raw_feed)}"
            )
        verify(match.group(1).decode("ascii"), raw_feed[:signed_length], "appcast feed")

    print(
        "update feed validated: "
        f"version={args.version} build={args.build_number} "
        f"enclosure={args.expected_enclosure_url} "
        f"feed_signed={'yes' if match else 'no'} "
        f"key={bundle['public_key'][:12]}…"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--artifact", required=True, help="the finalized DMG the feed points at")
    parser.add_argument("--app", required=True, help="candidate .app whose embedded key must match")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--minimum-macos", required=True)
    parser.add_argument("--architectures", required=True)
    parser.add_argument("--expected-enclosure-url", required=True)
    args = parser.parse_args()

    try:
        validate(args)
    except FeedValidationError as error:
        print(f"update feed validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
