#!/usr/bin/env python3
"""Generate deterministic JSON records for Niko Music Hub releases."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def write_json(path: str, payload: dict[str, object]) -> None:
    output = Path(path)
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def manifest(args: argparse.Namespace) -> None:
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
            "artifact": args.artifact,
            "artifact_sha256": args.artifact_sha256,
            "checksum": f"{args.artifact}.sha256",
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
        "artifact",
        "artifact-sha256",
        "created-utc",
        "validation-status",
    ):
        manifest_parser.add_argument(f"--{name}", required=True)
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
