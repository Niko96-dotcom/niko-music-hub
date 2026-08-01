#!/usr/bin/env python3
"""Generate deterministic JSON records for Niko Music Hub releases."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


def write_json(path: str, payload: dict[str, object]) -> None:
    output = Path(path)
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_architectures(raw: str) -> list[str]:
    values = sorted({value for value in raw.replace(",", " ").split() if value})
    if not values:
        raise SystemExit("manifest requires at least one release architecture")
    if any(value not in {"arm64", "x86_64"} for value in values):
        raise SystemExit(f"manifest contains unsupported release architecture(s): {values!r}")
    return values


def parse_minimum_macos(raw: str) -> str:
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", raw):
        raise SystemExit(f"manifest minimum macOS version is invalid: {raw!r}")
    return raw


def manifest(args: argparse.Namespace) -> None:
    if args.artifact_size <= 0:
        raise SystemExit("manifest artifact size must be positive")
    write_json(
        args.output,
        {
            "schema_version": 1,
            "product": "Niko Music Hub",
            "artifact_contract": "DMG containing NikoMusicHub.app",
            "public_release": args.public_release,
            "version": args.version,
            "bundle_id": args.bundle_id,
            "tag": args.tag,
            "commit": args.commit,
            "build_id": args.build_id,
            "build_number": args.build_number,
            "architectures": parse_architectures(args.architectures),
            "minimum_macos": parse_minimum_macos(args.minimum_macos),
            "artifact": args.artifact,
            "artifact_size_bytes": args.artifact_size,
            "artifact_sha256": args.artifact_sha256,
            "checksum": f"{args.artifact}.sha256",
            "signing": {
                "identity": args.signing_identity,
                "hardened_runtime": args.public_release,
                "notarization": "stapled" if args.public_release else "not-applicable",
            },
            "created_utc": args.created_utc,
            "validation_status": args.validation_status,
        },
    )


def approval(args: argparse.Namespace) -> None:
    gates = []
    for encoded in args.gate:
        parts = encoded.split("|", 3)
        if len(parts) != 4 or not all(parts):
            raise SystemExit(f"invalid --gate value: {encoded!r}")
        gates.append(
            {
                "name": parts[0],
                "command": parts[1],
                "result": parts[2],
                "completed_utc": parts[3],
            }
        )
    if not gates or any(gate["result"] not in {"passed", "emergency-override"} for gate in gates):
        raise SystemExit("approval record requires explicit passed or emergency-override gates")
    if any(gate["result"] == "emergency-override" for gate in gates) and not args.emergency_reason:
        raise SystemExit("emergency override gates require --emergency-reason")

    write_json(
        args.output,
        {
            "schema_version": 1,
            "product": "Niko Music Hub",
            "release_approved": True,
            "version": args.version,
            "bundle_id": args.bundle_id,
            "tag": args.tag,
            "commit": args.commit,
            "artifact": args.artifact,
            "artifact_sha256": args.artifact_sha256,
            "manifest": args.manifest,
            "manifest_sha256": args.manifest_sha256,
            "release_approval": {
                "machine": args.machine,
                "created_utc": args.created_utc,
                "emergency_override": bool(args.emergency_reason),
                "emergency_reason": args.emergency_reason or None,
            },
            "uat_evidence": {
                "file": args.uat_file,
                "sha256": args.uat_sha256,
                "approved_by": args.uat_approved_by,
                "approved_at_utc": args.uat_approved_at_utc,
            },
            "gates": gates,
        },
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)

    manifest_parser = commands.add_parser("manifest")
    for name in (
        "output",
        "version",
        "bundle-id",
        "tag",
        "commit",
        "build-id",
        "build-number",
        "architectures",
        "minimum-macos",
        "artifact",
        "artifact-sha256",
        "created-utc",
        "signing-identity",
        "validation-status",
    ):
        manifest_parser.add_argument(f"--{name}", required=True)
    manifest_parser.add_argument("--artifact-size", type=int, required=True)
    manifest_parser.add_argument("--public-release", action="store_true")
    manifest_parser.set_defaults(handler=manifest)

    approval_parser = commands.add_parser("approval")
    for name in (
        "output",
        "version",
        "bundle-id",
        "tag",
        "commit",
        "artifact",
        "artifact-sha256",
        "manifest",
        "manifest-sha256",
        "machine",
        "created-utc",
        "uat-file",
        "uat-sha256",
        "uat-approved-by",
        "uat-approved-at-utc",
    ):
        approval_parser.add_argument(f"--{name}", required=True)
    approval_parser.add_argument("--emergency-reason", default="")
    approval_parser.add_argument("--gate", action="append", default=[])
    approval_parser.set_defaults(handler=approval)
    return root


def main() -> None:
    args = parser().parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
