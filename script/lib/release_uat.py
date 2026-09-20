#!/usr/bin/env python3
"""Shared pure semantic validator for release UAT evidence.

Single source of truth for UAT semantics used by both
script/validate-release-uat.sh (standalone, one byte snapshot) and
script/validate-release-approval.sh (same bytes that were hashed).

Acceptance is evidence-backed AI computer-use per
docs/ai-acceptance-testing.md (owner-authorized; no mandatory human
approver). approved_by accepts any truthful non-placeholder executor
identifier, including an AI agent/session identifier (never a human
name the executor is not); it must never impersonate a human. Schema
stays schema_version int 1 with exactly the ten required checks; no
new schema is introduced and pending/failed requirements are not
weakened.

Strict types: schema_version must be int 1 (not "1", not True),
hardened_runtime must be boolean True (not "true", not 1), all other
identity fields must be exact strings. Placeholder/blank/whitespace
approved_by and machine values (TODO, TODO_*, REPLACE_WITH_*, empty)
are rejected coherently.
"""

from __future__ import annotations

import re

TIMESTAMP_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")


def is_placeholder_or_blank(value: object) -> bool:
    """True when an executor-owned free-text field is still a template value.

    AI agent/session identifiers are accepted; TODO, TODO_*, REPLACE_WITH_*,
    blank, and whitespace-only values are rejected.
    """
    if not isinstance(value, str):
        return True
    stripped = value.strip()
    if not stripped:
        return True
    if stripped == "TODO" or stripped.startswith("TODO"):
        return True
    if stripped.startswith("REPLACE_WITH_"):
        return True
    return False


def validate_uat(
    payload: dict,
    version: str,
    bundle_id: str,
    commit: str,
    expected_build_id: str,
    expected_signing_identity: str,
    required_checks: list[str],
) -> None:
    """Validate UAT semantics; raises SystemExit with a stable message.

    approved_by may be an AI agent/session identifier or the responsible
    operator, provided it is truthful, non-placeholder, and never
    impersonates a human. Schema, exact ten-check, and fail-closed
    (pending/failed reject) semantics are unchanged.
    """
    # schema_version must be int 1, not string "1" and not bool True
    # (True == 1 in Python, so exclude bools explicitly).
    schema = payload.get("schema_version")
    if schema != 1 or isinstance(schema, bool):
        raise SystemExit(
            f"release UAT evidence needs schema_version=1 (UAT schema_version mismatch: {schema!r} != 1)"
        )
    if payload.get("version") != version:
        raise SystemExit(
            f"release UAT evidence version does not match {version!r} "
            f"(UAT version mismatch: {payload.get('version')!r} != {version!r})"
        )
    if payload.get("commit") != commit:
        raise SystemExit(
            f"release UAT evidence commit does not match {commit!r} "
            f"(UAT commit mismatch: {payload.get('commit')!r} != {commit!r})"
        )
    if payload.get("bundle_id") != bundle_id:
        raise SystemExit(
            f"release UAT evidence bundle_id does not match {bundle_id!r} "
            f"(UAT bundle_id mismatch: {payload.get('bundle_id')!r} != {bundle_id!r})"
        )
    if payload.get("status") != "approved":
        raise SystemExit(
            f"release UAT evidence status must be approved "
            f"(UAT status must be approved (was {payload.get('status')!r}))"
        )
    approver = payload.get("approved_by")
    if is_placeholder_or_blank(approver):
        raise SystemExit(
            f"release UAT evidence needs a real approved_by value "
            f"(UAT evidence needs a real approved_by value (was {approver!r}))"
        )
    approved_at = payload.get("approved_at_utc")
    if not isinstance(approved_at, str) or not TIMESTAMP_RE.match(approved_at):
        raise SystemExit(
            f"release UAT approved_at_utc must be an ISO-8601 UTC timestamp "
            f"(UAT approved_at_utc must be an ISO-8601 UTC timestamp (was {approved_at!r}))"
        )
    machine = payload.get("machine")
    if is_placeholder_or_blank(machine):
        raise SystemExit(
            f"release UAT evidence needs the tested machine description "
            f"(UAT evidence needs the tested machine description (was {machine!r}))"
        )
    tested = payload.get("tested_build")
    if not isinstance(tested, dict):
        raise SystemExit(
            f"release UAT tested_build.build_id must be exactly {expected_build_id!r} "
            f"(UAT tested_build must be an object (was {tested!r}))"
        )
    if tested.get("build_id") != expected_build_id:
        raise SystemExit(
            f"release UAT tested_build.build_id must be exactly {expected_build_id!r} "
            f"for commit {commit!r} (stale builds from other commits do not transfer; "
            f"was {tested.get('build_id')!r}; "
            f"UAT tested_build.build_id mismatch)"
        )
    if tested.get("build_configuration") != "release":
        raise SystemExit(
            f"release UAT must be run on a release-configuration build "
            f"(tested_build.build_configuration was {tested.get('build_configuration')!r}; "
            f"UAT must be run on a release-configuration build)"
        )
    tested_signing = tested.get("signing_identity")
    if expected_signing_identity:
        if not expected_signing_identity.startswith("Developer ID Application:"):
            raise SystemExit(
                f"explicit --expected-signing-identity must be a Developer ID Application identity "
                f"(was {expected_signing_identity!r})"
            )
        if not isinstance(tested_signing, str) or not tested_signing.startswith(
            "Developer ID Application:"
        ):
            raise SystemExit(
                f"release UAT must be run on a Developer ID signed build; ad-hoc builds change "
                f"TCC identity on every rebuild and skip hardened runtime "
                f"(tested_build.signing_identity was {tested_signing!r}; "
                f"UAT must be run on a Developer ID signed build)"
            )
        if tested_signing != expected_signing_identity:
            raise SystemExit(
                f"release UAT tested_build.signing_identity must be exactly "
                f"{expected_signing_identity!r} (intended candidate identity; "
                f"was {tested_signing!r}; UAT tested_build.signing_identity mismatch)"
            )
    else:
        if not isinstance(tested_signing, str) or not tested_signing.startswith(
            "Developer ID Application:"
        ):
            raise SystemExit(
                f"release UAT must be run on a Developer ID signed build; ad-hoc builds change "
                f"TCC identity on every rebuild and skip hardened runtime "
                f"(tested_build.signing_identity was {tested_signing!r}; "
                f"UAT must be run on a Developer ID signed build)"
            )
    if tested.get("hardened_runtime") is not True:
        raise SystemExit(
            f"release UAT must be run on a hardened-runtime build "
            f"(tested_build.hardened_runtime was {tested.get('hardened_runtime')!r}; "
            f"UAT must be run on a hardened-runtime build)"
        )
    checks = payload.get("checks")
    if not isinstance(checks, dict):
        raise SystemExit("release UAT evidence checks must be an object (UAT checks must be an object)")
    if set(checks) != set(required_checks):
        raise SystemExit(
            f"release UAT evidence has unknown checks: "
            f"missing={sorted(set(required_checks) - set(checks))!r} "
            f"unknown={sorted(set(checks) - set(required_checks))!r} "
            f"(UAT checks must be exactly {sorted(required_checks)!r})"
        )
    for name in required_checks:
        if checks.get(name) != "passed":
            raise SystemExit(
                f"release UAT evidence check {name!r} must be passed "
                f"(was {checks.get(name)!r}; UAT check {name!r} must be passed)"
            )
