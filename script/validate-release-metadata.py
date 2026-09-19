#!/usr/bin/env /usr/bin/python3
"""Validate release metadata against the resolved dependency pins.

Every release run must prove that SBOM.spdx.json, THIRD_PARTY_NOTICES.md, and
SOURCE_PROVENANCE.md still describe exactly the dependencies locked in
Package.resolved at the current VERSION. A version bump, URL move, or revision
advance that updates the lockfile but not the commercial records would
otherwise ship stale provenance silently, so any drift fails closed here
instead of during publication.

This validator is read-only: it never regenerates tracked files and never
changes the published asset contract. Run it via
script/release-version-verify.sh on every release run.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


class MetadataValidationError(Exception):
    pass


def _norm_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def _norm_location(value: str) -> str:
    text = value.strip()
    if text.startswith("git+"):
        text = text[4:]
    text = text.split("@")[0]
    if text.endswith(".git"):
        text = text[:-4]
    return text.rstrip("/")


def _location_path(location: str) -> str:
    return location.split("://", 1)[-1].rstrip("/")


def load_version(root: Path, override: str | None) -> str:
    if override is not None:
        version = override.strip()
    else:
        version_file = root / "VERSION"
        if not version_file.is_file():
            raise MetadataValidationError(f"missing canonical VERSION file: {version_file}")
        version = version_file.read_text(encoding="utf-8").strip()
    if not version:
        raise MetadataValidationError("release version is empty")
    return version


def load_pins(resolved_path: Path) -> list[dict]:
    if not resolved_path.is_file():
        raise MetadataValidationError(f"missing Package.resolved: {resolved_path}")
    try:
        payload = json.loads(resolved_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MetadataValidationError(f"could not parse {resolved_path}: {error}") from error
    pins = payload.get("pins")
    if not isinstance(pins, list):
        raise MetadataValidationError(f"{resolved_path} has no pins list")
    result = []
    for entry in pins:
        if not isinstance(entry, dict):
            raise MetadataValidationError(f"{resolved_path} contains a malformed pin record")
        identity = entry.get("identity") or ""
        location = entry.get("location") or ""
        state = entry.get("state") or {}
        revision = state.get("revision") or "" if isinstance(state, dict) else ""
        version = state.get("version") or "" if isinstance(state, dict) else ""
        if not identity or not location or not revision or not version:
            raise MetadataValidationError(
                f"{resolved_path} pin is missing identity/location/revision/version: {entry!r}"
            )
        result.append(
            {"identity": identity, "location": location, "revision": revision, "version": version}
        )
    return result


def load_sbom(sbom_path: Path) -> dict:
    if not sbom_path.is_file():
        raise MetadataValidationError(f"missing SBOM record: {sbom_path}")
    try:
        return json.loads(sbom_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MetadataValidationError(f"could not parse {sbom_path}: {error}") from error


def validate(args: argparse.Namespace) -> None:
    root = Path(args.root)
    sbom_path = Path(args.sbom) if args.sbom else root / "SBOM.spdx.json"
    resolved_path = Path(args.resolved) if args.resolved else root / "Package.resolved"
    notices_path = Path(args.notices) if args.notices else root / "THIRD_PARTY_NOTICES.md"
    provenance_path = (
        Path(args.provenance) if args.provenance else root / "SOURCE_PROVENANCE.md"
    )

    version = load_version(root, args.version)
    pins = load_pins(resolved_path)
    sbom = load_sbom(sbom_path)

    failures: list[str] = []

    expected_doc_name = f"Niko-Music-Hub-{version}-source"
    if sbom.get("name") != expected_doc_name:
        failures.append(
            f"SBOM document name is {sbom.get('name')!r}, expected {expected_doc_name!r}"
        )

    packages = sbom.get("packages")
    if not isinstance(packages, list) or not packages:
        raise MetadataValidationError(f"{sbom_path} has no packages list")

    root_packages = [p for p in packages if isinstance(p, dict) and _norm_name(str(p.get("name") or "")) == "nikomusichub"]
    if len(root_packages) != 1:
        failures.append(
            f"SBOM must contain exactly one Niko Music Hub root package, found {len(root_packages)}"
        )
        root_package = root_packages[0] if root_packages else {}
    else:
        root_package = root_packages[0]
    if isinstance(root_package, dict) and root_package.get("versionInfo") != version:
        failures.append(
            f"SBOM root package versionInfo is {root_package.get('versionInfo')!r}, expected VERSION={version!r}"
        )

    dep_packages = [
        p
        for p in packages
        if isinstance(p, dict) and _norm_name(str(p.get("name") or "")) != "nikomusichub"
    ]
    by_norm_name: dict[str, dict] = {}
    dep_norm_counts: dict[str, int] = {}
    for dep in dep_packages:
        dep_key = _norm_name(str(dep.get("name") or ""))
        dep_norm_counts[dep_key] = dep_norm_counts.get(dep_key, 0) + 1
        if dep_key not in by_norm_name:
            by_norm_name[dep_key] = dep
    for pin in pins:
        pin_key = _norm_name(pin["identity"])
        if dep_norm_counts.get(pin_key, 0) > 1:
            failures.append(
                f"SBOM contains duplicate packages for resolved dependency {pin['identity']!r} "
                f"(normalized {pin_key!r}, found {dep_norm_counts[pin_key]}); refusing to ship "
                "ambiguous duplicate dependency metadata"
            )

    for pin in pins:
        candidate = by_norm_name.get(_norm_name(pin["identity"]))
        if candidate is None:
            failures.append(
                f"SBOM is missing a package for resolved dependency {pin['identity']!r} "
                f"{pin['version']!r}; refusing to ship undocumented dependency metadata"
            )
            continue
        if candidate.get("versionInfo") != pin["version"]:
            failures.append(
                f"SBOM package {candidate.get('name')!r} versionInfo is "
                f"{candidate.get('versionInfo')!r}, expected resolved {pin['version']!r} "
                f"for {pin['identity']!r}"
            )
        download = str(candidate.get("downloadLocation") or "")
        if _norm_location(download) != _norm_location(pin["location"]):
            failures.append(
                f"SBOM package {candidate.get('name')!r} downloadLocation {download!r} "
                f"does not match resolved location {pin['location']!r}"
            )
        if pin["revision"] not in download:
            failures.append(
                f"SBOM package {candidate.get('name')!r} downloadLocation does not "
                f"contain resolved revision {pin['revision']!r}"
            )

    pin_norm_names = {_norm_name(p["identity"]) for p in pins}
    for package in dep_packages:
        if _norm_name(str(package.get("name") or "")) not in pin_norm_names:
            failures.append(
                f"SBOM has extra package {package.get('name')!r} with no matching "
                "Package.resolved pin; refusing to ship undocumented dependency metadata"
            )

    relationships = sbom.get("relationships")
    if not isinstance(relationships, list):
        failures.append(f"{sbom_path} has no relationships list")
        relationships = []
    depends_on = {
        r.get("relatedSpdxElement")
        for r in relationships
        if isinstance(r, dict) and r.get("relationshipType") == "DEPENDS_ON"
    }
    for package in dep_packages:
        spdx_id = package.get("SPDXID")
        if spdx_id not in depends_on:
            failures.append(
                f"SBOM has no DEPENDS_ON relationship for dependency package "
                f"{package.get('name')!r} ({spdx_id!r})"
            )

    for path in (notices_path, provenance_path):
        if not path.is_file():
            failures.append(f"missing commercial record: {path}")
    notices_text = notices_path.read_text(encoding="utf-8") if notices_path.is_file() else ""
    provenance_text = provenance_path.read_text(encoding="utf-8") if provenance_path.is_file() else ""

    if notices_path.is_file() and "Package.resolved" not in notices_text:
        failures.append(
            f"{notices_path} does not reference Package.resolved; the exact revision "
            "pin has no notice coverage"
        )
    for pin in pins:
        if pin["identity"].lower() not in notices_text.lower():
            failures.append(
                f"{notices_path} has no coverage for resolved dependency {pin['identity']!r}"
            )
        if pin["version"] not in notices_text:
            failures.append(
                f"{notices_path} does not mention resolved version {pin['version']!r} "
                f"for {pin['identity']!r}; notices drifted from Package.resolved"
            )
        if _location_path(pin["location"]) not in notices_text:
            failures.append(
                f"{notices_path} does not mention resolved source location "
                f"{pin['location']!r} for {pin['identity']!r}"
            )

    if provenance_path.is_file():
        for marker in ("Package.resolved", "Package.swift"):
            if marker not in provenance_text:
                failures.append(
                    f"{provenance_path} does not reference {marker}; dependency "
                    "provenance coverage drifted"
                )
    for pin in pins:
        if pin["identity"].lower() not in provenance_text.lower():
            failures.append(
                f"{provenance_path} has no coverage for resolved dependency {pin['identity']!r}"
            )

    if failures:
        raise MetadataValidationError(
            "release metadata validation failed:\n" + "\n".join(f"- {failure}" for failure in failures)
        )

    print(
        "release metadata validated: "
        f"version={version} dependencies={len(pins)} "
        f"({', '.join(sorted(p['identity'] + '@' + p['version'] for p in pins)) or 'none'})"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--version", default=None, help="override the VERSION file (fixture tests)")
    parser.add_argument("--sbom", default=None)
    parser.add_argument("--resolved", default=None)
    parser.add_argument("--notices", default=None)
    parser.add_argument("--provenance", default=None)
    args = parser.parse_args()
    try:
        validate(args)
    except MetadataValidationError as error:
        print(f"{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
