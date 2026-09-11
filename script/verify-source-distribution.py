#!/usr/bin/env python3
"""Fail-closed secret, PII, license, provenance, and manifest checks for buyer source trees."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


FORBIDDEN_TOP_LEVEL = {
    ".ai",
    ".build",
    ".codex",
    ".cursor",
    ".deslop",
    ".git",
    ".github",
    ".planning",
    "dist",
    "tmp",
    "AGENTS.md",
}
REQUIRED_FILES = {
    "BUNDLE_ID",
    "CHANGELOG.md",
    "LICENSE",
    "Package.swift",
    "README.md",
    "SBOM.spdx.json",
    "SOURCE_EXPORT_MANIFEST.json",
    "SOURCE_PROVENANCE.md",
    "THIRD_PARTY_NOTICES.md",
    "VERSION",
}
CONTENT_PATTERNS = {
    # Any home directory that is not an obvious placeholder is treated as a real
    # person's path. Fixtures use the placeholder names below on purpose.
    "personal home path": re.compile(
        r"/Users/(?!(?:example|tester|test|music|private-user|user|you|shared|someone|placeholder)(?:/|\b))"
        r"[A-Za-z0-9_.-]+(?:/|\b)",
        re.IGNORECASE,
    ),
    "private machine name": re.compile(r"\b(?:MacBook|Mac Studio)\b", re.IGNORECASE),
    "private workflow state": re.compile(r"(?:^|/)\.(?:ai|planning|cursor|deslop)(?:/|$)"),
    "credential-shaped value": re.compile(
        r"(?:AKIA[0-9A-Z]{16}|-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|"
        r"xox[baprs]-[A-Za-z0-9-]{10,}|gh[pousr]_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{32,})"
    ),
}
FORBIDDEN_SUFFIXES = {".env", ".key", ".mobileprovision", ".p12", ".pem", ".pfx", ".xcresult"}
CONTENT_PATTERN_EXEMPTIONS = {
    Path("Tests/test_source_distribution_scripts.sh"),
    Path("script/public-tree-hygiene.sh"),
    Path("script/verify-source-distribution.py"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def scan_tree(root: Path) -> list[str]:
    failures: list[str] = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if relative.parts and relative.parts[0] in FORBIDDEN_TOP_LEVEL:
            failures.append(f"{relative}: forbidden private/build path")
            continue
        if path.is_symlink():
            failures.append(f"{relative}: symbolic links are not allowed in the source-sale archive")
            continue
        if not path.is_file():
            continue
        if path.name == ".DS_Store" or path.suffix.lower() in FORBIDDEN_SUFFIXES:
            failures.append(f"{relative}: forbidden file type")
        if relative in CONTENT_PATTERN_EXEMPTIONS:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for label, pattern in CONTENT_PATTERNS.items():
            if pattern.search(text):
                failures.append(f"{relative}: contains {label}")
    return failures


def verify_manifest(root: Path) -> list[str]:
    failures: list[str] = []
    manifest_path = root / "SOURCE_EXPORT_MANIFEST.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"SOURCE_EXPORT_MANIFEST.json: {error}"]

    if manifest.get("schema_version") != 1:
        failures.append("SOURCE_EXPORT_MANIFEST.json: schema_version must be 1")
    if manifest.get("version") != (root / "VERSION").read_text().strip():
        failures.append("SOURCE_EXPORT_MANIFEST.json: version mismatch")
    if manifest.get("bundle_id") != (root / "BUNDLE_ID").read_text().strip():
        failures.append("SOURCE_EXPORT_MANIFEST.json: bundle_id mismatch")

    expected_files = manifest.get("files_sha256")
    if not isinstance(expected_files, dict):
        return failures + ["SOURCE_EXPORT_MANIFEST.json: files_sha256 must be an object"]
    actual_paths = {
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file() and path != manifest_path
    }
    if actual_paths != set(expected_files):
        failures.append("SOURCE_EXPORT_MANIFEST.json: file inventory does not match the exported tree")
    for relative, expected_hash in expected_files.items():
        path = root / relative
        if path.is_file() and sha256(path) != expected_hash:
            failures.append(f"{relative}: SHA-256 does not match export manifest")
    return failures


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tree", required=True)
    parser.add_argument("--scan-only", action="store_true")
    parser.add_argument("--candidate", action="store_true")
    args = parser.parse_args()

    root = Path(args.tree).resolve()
    if not root.is_dir():
        raise SystemExit(f"source distribution tree missing: {root}")
    failures = scan_tree(root)

    if not args.scan_only:
        missing = sorted(name for name in REQUIRED_FILES if not (root / name).is_file())
        failures.extend(f"{name}: required source-sale record missing" for name in missing)
        if not missing:
            failures.extend(verify_manifest(root))
            try:
                sbom = json.loads((root / "SBOM.spdx.json").read_text(encoding="utf-8"))
                if sbom.get("spdxVersion") != "SPDX-2.3":
                    failures.append("SBOM.spdx.json: expected SPDX-2.3")
                packages = sbom.get("packages", [])
                if not packages or packages[0].get("versionInfo") != (root / "VERSION").read_text().strip():
                    failures.append("SBOM.spdx.json: package version must match VERSION")
            except (OSError, json.JSONDecodeError) as error:
                failures.append(f"SBOM.spdx.json: {error}")

        approval = root / "SOURCE_SALE_APPROVAL.json"
        candidate_notice = root / "SOURCE_SALE_APPROVAL_REQUIRED.md"
        if args.candidate:
            if approval.exists() or not candidate_notice.is_file():
                failures.append("candidate export must contain only SOURCE_SALE_APPROVAL_REQUIRED.md")
        elif not approval.is_file() or candidate_notice.exists():
            failures.append("sale export requires SOURCE_SALE_APPROVAL.json and no candidate notice")

    if failures:
        print("source distribution verification failed:")
        for failure in failures:
            print(f"  {failure}")
        raise SystemExit(1)
    mode = "scan-only" if args.scan_only else ("candidate" if args.candidate else "approved")
    count = sum(1 for path in root.rglob("*") if path.is_file())
    print(f"source distribution ok: mode={mode} files={count} tree={root}")


if __name__ == "__main__":
    main()
