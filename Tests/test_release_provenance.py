#!/usr/bin/env python3
"""Behavioral provenance tests for the release UAT/approval validators.

Executes the actual validators (script/validate-release-uat.sh and
script/validate-release-approval.sh) on disposable fixture artifacts,
UAT evidence, manifests, and approvals in a temporary directory.
Hermetic and local-only safe: fake Developer ID team names only,
no network, no keychain, no real UAT.

Run:
  python3 Tests/test_release_provenance.py
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
UAT_VALIDATOR = ROOT / "script" / "validate-release-uat.sh"
APPROVAL_VALIDATOR = ROOT / "script" / "validate-release-approval.sh"
GENERATOR = ROOT / "script" / "generate-release-record.py"

VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
BUNDLE_ID = (ROOT / "BUNDLE_ID").read_text(encoding="utf-8").strip()

# Exact contract under test. These literals must match
# script/lib/release_gates.sh; behavior (not source text) proves it.
REQUIRED_GATES = [
    "clean-tagged-checkout",
    "consolidated-mac-uat",
    "debug-ci",
    "user-e2e",
    "release-configuration",
    "thread-sanitizer",
    "release-identity",
    "release-platform-contract",
    "public-tree-hygiene",
    "sign-notarize-staple",
    "artifact-validation",
    "update-feed",
]
OVERRIDABLE_GATES = {
    "debug-ci",
    "user-e2e",
    "release-configuration",
    "thread-sanitizer",
}
REQUIRED_CHECKS = [
    "clean_install",
    "upgrade_preserves_settings",
    "uninstall",
    "launch_at_login",
    "privacy_permissions",
    "recorder_real_audio",
    "downloader_live",
    "archive_read_only",
    "output_handoffs",
    "e2e_user_smoke",
]

# Fixed fake commit; validators fall back to first-12 chars when the sha is
# not in the local repo, so the canonical build id is deterministic.
FAKE_COMMIT = "0123456789abcdef0123456789abcdef01234567"
FAKE_SHORT = FAKE_COMMIT[:12]
CANONICAL_BUILD_ID = f"{VERSION}+{FAKE_SHORT}"
TEST_IDENTITY = "Developer ID Application: Release Test (TEAM)"
OTHER_IDENTITY = "Developer ID Application: Release Test (OTHER)"
TIMESTAMP = "2026-07-13T12:00:00Z"
# Explicit truthful AI executor identifier: non-placeholder free text the
# existing validator already accepts (no schema change). Never a human name.
AI_ACTOR = "ai-acceptance Muse Spark session-304774ee"


def clean_env() -> dict[str, str]:
    env = dict(os.environ)
    for key in (
        "NMH_DEVELOPER_ID_APPLICATION",
        "NMH_NOTARY_PROFILE",
        "NMH_RELEASE_UAT_EVIDENCE",
    ):
        env.pop(key, None)
    return env


def run_cmd(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=clean_env(),
    )


def sha_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_uat(path: pathlib.Path, signing_identity: str = TEST_IDENTITY) -> None:
    payload = {
        "schema_version": 1,
        "version": VERSION,
        "commit": FAKE_COMMIT,
        "bundle_id": BUNDLE_ID,
        "status": "approved",
        "approved_by": "Release Test",
        "approved_at_utc": TIMESTAMP,
        "machine": "arm64 macOS test machine",
        "tested_build": {
            "build_id": CANONICAL_BUILD_ID,
            "build_configuration": "release",
            "signing_identity": signing_identity,
            "hardened_runtime": True,
        },
        "checks": {name: "passed" for name in REQUIRED_CHECKS},
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def mutate_json(path: pathlib.Path, mutate) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    mutate(payload)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def generate_manifest(
    output: pathlib.Path,
    artifact_name: str,
    artifact_sha: str,
    artifact_size: int,
    signing_identity: str = TEST_IDENTITY,
) -> None:
    result = run_cmd(
        [
            sys.executable,
            str(GENERATOR),
            "manifest",
            "--output",
            str(output),
            "--version",
            VERSION,
            "--bundle-id",
            BUNDLE_ID,
            "--tag",
            f"v{VERSION}",
            "--commit",
            FAKE_COMMIT,
            "--build-id",
            CANONICAL_BUILD_ID,
            "--build-number",
            "1",
            "--architectures",
            "arm64",
            "--minimum-macos",
            "14.0",
            "--artifact",
            artifact_name,
            "--artifact-size",
            str(artifact_size),
            "--artifact-sha256",
            artifact_sha,
            "--created-utc",
            TIMESTAMP,
            "--signing-identity",
            signing_identity,
            "--validation-status",
            "passed",
            "--public-release",
        ]
    )
    assert result.returncode == 0, f"manifest generator failed: {result.stderr}"


def template_sentinels() -> tuple[str, str]:
    payload = json.loads((ROOT / "docs" / "release-uat-evidence.template.json").read_text(encoding="utf-8"))
    return str(payload["approved_by"]), str(payload["machine"])


def generate_approval(
    output: pathlib.Path,
    artifact_name: str,
    artifact_sha: str,
    manifest_name: str,
    manifest_sha: str,
    uat_name: str,
    uat_sha: str,
    gate_results: dict[str, str] | None = None,
    emergency_reason: str = "",
    uat_approved_by: str = "Release Test",
) -> None:
    results = gate_results or {}
    args = [
        sys.executable,
        str(GENERATOR),
        "approval",
        "--output",
        str(output),
        "--version",
        VERSION,
        "--bundle-id",
        BUNDLE_ID,
        "--tag",
        f"v{VERSION}",
        "--commit",
        FAKE_COMMIT,
        "--artifact",
        artifact_name,
        "--artifact-sha256",
        artifact_sha,
        "--manifest",
        manifest_name,
        "--manifest-sha256",
        manifest_sha,
        "--machine",
        "arm64 macOS test machine",
        "--created-utc",
        TIMESTAMP,
        "--uat-file",
        uat_name,
        "--uat-sha256",
        uat_sha,
        "--uat-approved-by",
        uat_approved_by,
        "--uat-approved-at-utc",
        TIMESTAMP,
    ]
    if emergency_reason:
        args += ["--emergency-reason", emergency_reason]
    for gate in REQUIRED_GATES:
        result = results.get(gate, "passed")
        args += ["--gate", f"{gate}|cmd-{gate}|{result}|{TIMESTAMP}"]
    completed = run_cmd(args)
    assert completed.returncode == 0, f"approval generator failed: {completed.stderr}"


def build_valid_bundle(tmp: pathlib.Path, manifest_identity: str = TEST_IDENTITY):
    artifact = tmp / f"NikoMusicHub-{VERSION}.dmg"
    artifact.write_bytes(b"provenance-fixture-artifact-bytes")
    artifact_sha = sha_file(artifact)
    manifest = tmp / f"NikoMusicHub-{VERSION}-manifest.json"
    generate_manifest(
        manifest,
        artifact.name,
        artifact_sha,
        artifact.stat().st_size,
        signing_identity=manifest_identity,
    )
    uat = tmp / "uat.json"
    write_uat(uat)
    approval = tmp / f"NikoMusicHub-{VERSION}-release-approval.json"
    generate_approval(
        approval,
        artifact.name,
        artifact_sha,
        manifest.name,
        sha_file(manifest),
        uat.name,
        sha_file(uat),
    )
    return artifact, manifest, uat, approval


def uat_args(uat: pathlib.Path, extra: list[str] | None = None) -> list[str]:
    cmd = [
        "bash",
        str(UAT_VALIDATOR),
        "--evidence",
        str(uat),
        "--commit",
        FAKE_COMMIT,
        "--expected-signing-identity",
        TEST_IDENTITY,
        "--expected-build-id",
        CANONICAL_BUILD_ID,
    ]
    if extra:
        # Replace defaults when the case overrides one of them.
        i = 0
        while i < len(extra):
            flag = extra[i]
            value = extra[i + 1] if i + 1 < len(extra) else ""
            if flag in ("--commit", "--expected-signing-identity", "--expected-build-id"):
                j = 0
                while j < len(cmd):
                    if cmd[j] == flag:
                        cmd[j + 1] = value
                        break
                    j += 1
            else:
                cmd += [flag, value] if value else [flag]
            i += 2
    return cmd


def approval_args(
    approval: pathlib.Path,
    artifact: pathlib.Path,
    manifest: pathlib.Path,
    uat: pathlib.Path,
    extra: list[str] | None = None,
) -> list[str]:
    cmd = [
        "bash",
        str(APPROVAL_VALIDATOR),
        "--approval",
        str(approval),
        "--artifact",
        str(artifact),
        "--manifest",
        str(manifest),
        "--uat",
        str(uat),
        "--commit",
        FAKE_COMMIT,
        "--expected-build-id",
        CANONICAL_BUILD_ID,
        "--expected-signing-identity",
        TEST_IDENTITY,
    ]
    if extra:
        i = 0
        while i < len(extra):
            flag = extra[i]
            value = extra[i + 1] if i + 1 < len(extra) else ""
            if flag in ("--commit", "--expected-signing-identity", "--expected-build-id"):
                j = 0
                while j < len(cmd):
                    if cmd[j] == flag:
                        cmd[j + 1] = value
                        break
                    j += 1
            else:
                cmd += [flag, value] if value else [flag]
            i += 2
    return cmd


class ProvenanceBehaviorTests(unittest.TestCase):
    def test_uat_validator_accepts_valid_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat)
            result = run_cmd(uat_args(uat))
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("release UAT evidence ok", result.stdout)

    def test_uat_validator_accepts_explicit_ai_actor(self) -> None:
        # No mandatory human approver: a truthful non-placeholder AI
        # agent/session identifier passes the standalone validator under the
        # existing schema (no new schema, no weakened requirement).
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", AI_ACTOR))
            result = run_cmd(uat_args(uat))
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("release UAT evidence ok", result.stdout)

    def test_approval_accepts_explicit_ai_actor(self) -> None:
        # Same AI actor passes the final approval validator when every other
        # byte (hashes, exact ten checks, build/signing binding) is valid.
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", AI_ACTOR))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
                uat_approved_by=AI_ACTOR,
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("release approval ok", result.stdout)

    def test_ai_actor_pending_or_missing_checks_still_reject(self) -> None:
        # The AI actor confers no leniency: pending and missing checks still
        # fail closed in both validators, using the existing helpers.
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", AI_ACTOR))
            mutate_json(uat, lambda payload: payload["checks"].__setitem__("privacy_permissions", "pending"))
            standalone = run_cmd(uat_args(uat))
            self.assertNotEqual(standalone.returncode, 0)
            self.assertIn("must be passed", standalone.stderr)
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", AI_ACTOR))
            mutate_json(uat, lambda payload: payload["checks"].__setitem__("archive_read_only", "pending"))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
                uat_approved_by=AI_ACTOR,
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be passed", result.stderr)
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", AI_ACTOR))

            def drop_check(payload) -> None:
                del payload["checks"]["e2e_user_smoke"]

            mutate_json(uat, drop_check)
            standalone = run_cmd(uat_args(uat))
            self.assertNotEqual(standalone.returncode, 0)
            self.assertIn("unknown checks", standalone.stderr)
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", AI_ACTOR))

            def drop_check(payload) -> None:
                del payload["checks"]["e2e_user_smoke"]

            mutate_json(uat, drop_check)
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
                uat_approved_by=AI_ACTOR,
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown checks", result.stderr)

    def test_uat_rejects_inconsistent_expected_build_id(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat)
            bad = f"{VERSION}+000000000000"
            result = run_cmd(
                uat_args(uat, ["--expected-build-id", bad]),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not match canonical", result.stderr)

    def test_uat_rejects_adhoc_expected_identity(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat)
            result = run_cmd(
                uat_args(uat, ["--expected-signing-identity", "ad-hoc"]),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be a Developer ID", result.stderr)

    def test_uat_explicit_identity_still_requires_developer_id_shape(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat, signing_identity="ad-hoc")
            result = run_cmd(uat_args(uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Developer ID signed build", result.stderr)

    def test_approval_accepts_valid_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("release approval ok", result.stdout)

    def test_approval_rejects_inconsistent_expected_build_id(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            result = run_cmd(
                approval_args(
                    approval,
                    artifact,
                    manifest,
                    uat,
                    ["--expected-build-id", f"{VERSION}+000000000000"],
                )
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not match canonical", result.stderr)

    def test_approval_rejects_adhoc_expected_identity(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            result = run_cmd(
                approval_args(
                    approval, artifact, manifest, uat, ["--expected-signing-identity", "ad-hoc"]
                )
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be a Developer ID", result.stderr)

    def test_approval_rejects_mismatched_signing_team(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(
                tmp, manifest_identity=OTHER_IDENTITY
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest signing.identity mismatch", result.stderr)

    def test_approval_enforces_same_byte_uat_semantics(self) -> None:
        # The approval hash and the semantic checks must apply to the same
        # UAT bytes: rebuild the approval after mutating the UAT so hashes
        # match, and the validator must still reject the pending check.
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(uat, lambda payload: payload["checks"].__setitem__("privacy_permissions", "pending"))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be passed", result.stderr)

    def test_approval_narrow_override_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, _ = build_valid_bundle(tmp)
            approval = tmp / "override-approval.json"
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
                gate_results={name: "emergency-override" for name in OVERRIDABLE_GATES},
                emergency_reason="test emergency: hardware lab offline",
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertEqual(result.returncode, 0, msg=result.stderr)

    def test_approval_disallowed_override_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, _ = build_valid_bundle(tmp)
            approval = tmp / "bad-override-approval.json"
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
                gate_results={"sign-notarize-staple": "emergency-override"},
                emergency_reason="test disallowed override",
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("not emergency-overridable", result.stderr)

    def test_approval_requires_exact_gate_set(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            payload = json.loads(approval.read_text(encoding="utf-8"))
            payload["gates"] = [g for g in payload["gates"] if g["name"] != "update-feed"]
            approval.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing", result.stderr)

    def test_uat_rejects_template_sentinels(self) -> None:
        approver_sentinel, machine_sentinel = template_sentinels()
        self.assertTrue(approver_sentinel.startswith("TODO"))
        self.assertTrue(machine_sentinel.startswith("TODO"))
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            uat = tmp / "uat.json"
            write_uat(uat)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", approver_sentinel))
            result = run_cmd(uat_args(uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("real approved_by", result.stderr)
            write_uat(uat)
            mutate_json(uat, lambda payload: payload.__setitem__("machine", machine_sentinel))
            result = run_cmd(uat_args(uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tested machine description", result.stderr)

    def test_uat_rejects_placeholders_blanks_and_lax_types(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            for placeholder in ("TODO", "TODO_REAL_NAME_REQUIRED", "", "   ", "REPLACE_WITH_SOMEONE"):
                uat = tmp / "uat.json"
                write_uat(uat)
                mutate_json(uat, lambda payload, value=placeholder: payload.__setitem__("approved_by", value))
                result = run_cmd(uat_args(uat))
                self.assertNotEqual(result.returncode, 0, msg=f"approved_by={placeholder!r}")
                self.assertIn("real approved_by", result.stderr)
            uat = tmp / "uat.json"
            write_uat(uat)
            mutate_json(uat, lambda payload: payload.__setitem__("schema_version", "1"))
            result = run_cmd(uat_args(uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("schema_version", result.stderr)
            write_uat(uat)
            mutate_json(uat, lambda payload: payload["tested_build"].__setitem__("hardened_runtime", "true"))
            result = run_cmd(uat_args(uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hardened", result.stderr)
            write_uat(uat)
            mutate_json(uat, lambda payload: payload["tested_build"].__setitem__("hardened_runtime", 1))
            result = run_cmd(uat_args(uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hardened", result.stderr)

    def test_approval_rejects_template_machine_rehashed(self) -> None:
        _, machine_sentinel = template_sentinels()
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(uat, lambda payload: payload.__setitem__("machine", machine_sentinel))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tested machine description", result.stderr)
            self.assertNotIn("identity mismatch", result.stderr)

    def test_approval_rejects_template_approver_rehashed(self) -> None:
        approver_sentinel, _ = template_sentinels()
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(uat, lambda payload: payload.__setitem__("approved_by", approver_sentinel))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
                uat_approved_by=approver_sentinel,
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("real approved_by", result.stderr)
            self.assertNotIn("identity mismatch", result.stderr)

    def test_approval_rejects_lax_hardened_string_rehashed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(uat, lambda payload: payload["tested_build"].__setitem__("hardened_runtime", "true"))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hardened", result.stderr)
            # Both validators share strict types: standalone agrees.
            standalone = run_cmd(uat_args(uat))
            self.assertNotEqual(standalone.returncode, 0)
            self.assertIn("hardened", standalone.stderr)

    def test_approval_manifest_artifact_name_binding_rehashed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(manifest, lambda payload: payload.__setitem__("artifact", "evil-renamed.dmg"))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest artifact mismatch", result.stderr)
            self.assertNotIn("manifest_sha256", result.stderr)

    def test_approval_manifest_artifact_hash_binding_rehashed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(manifest, lambda payload: payload.__setitem__("artifact_sha256", "0" * 64))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest artifact_sha256 mismatch", result.stderr)
            self.assertNotIn("approval manifest_sha256 mismatch", result.stderr)

    def test_approval_manifest_tag_binding_rehashed(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            tmp = pathlib.Path(raw)
            artifact, manifest, uat, approval = build_valid_bundle(tmp)
            mutate_json(manifest, lambda payload: payload.__setitem__("tag", "v0.0.0-evil"))
            generate_approval(
                approval,
                artifact.name,
                sha_file(artifact),
                manifest.name,
                sha_file(manifest),
                uat.name,
                sha_file(uat),
            )
            result = run_cmd(approval_args(approval, artifact, manifest, uat))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest tag mismatch", result.stderr)
            self.assertNotIn("approval manifest_sha256 mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
