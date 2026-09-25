#!/usr/bin/env python3
"""Behavioral R1/R2/R4 pipeline provenance tests.

Exercises the actual orchestration/helper functions from
script/lib/release_snapshot.sh and script/release-env.sh against disposable
temp git fixture repositories with stubbed side effects. Proves:

- R1: pinned exact commit executes from an isolated snapshot; concurrent
  live mutations cannot enter the artifact/provenance.
- R2: UAT is frozen once before validation; hashing/final validation use the
  same frozen bytes even if the external original changes; final semantic
  validation rejects bad captured evidence (rehashed approval still fails).
- R4: production Sparkle public-key continuity rejects NMH_SPARKLE_* alternates
  and resolved-vs-pinned mismatches before build/publish; test/local overrides
  remain explicit.
- Isolated .build/output: snapshot lives outside RELEASE_DIR so rm -rf output
  cannot remove it; cleanup is safe/bounded and preserves working tree.

Hermetic, local-only safe: fake Developer ID names, no network, no keychain,
no signing/notary/publication. Never contacts real side effects: stubbed gh
that fails if invoked for publication paths.

Public mode refuses NMH_RELEASE_TEST_MODE (local-only keeps it for test
wrappers); orchestration invokes the production non-TEST_MODE branch with
fixture-only lifecycle/build stubs. No new public bypass env is created.

Run:
  python3 -m unittest discover -s Tests -p 'test_release_pipeline_provenance.py'
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SNAPSHOT_LIB = ROOT / "script" / "lib" / "release_snapshot.sh"
RELEASE_ENV = ROOT / "script" / "release-env.sh"
UAT_VALIDATOR = ROOT / "script" / "validate-release-uat.sh"
APPROVAL_VALIDATOR = ROOT / "script" / "validate-release-approval.sh"
GENERATOR = ROOT / "script" / "generate-release-record.py"

REAL_VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
REAL_BUNDLE_ID = (ROOT / "BUNDLE_ID").read_text(encoding="utf-8").strip()
REAL_SNAPSHOT_KEY = (ROOT / "SPARKLE_PUBLIC_ED_KEY").read_text(encoding="utf-8").strip()
ALT_KEY = base64.b64encode(bytes(32)).decode("ascii")

TEST_IDENTITY = "Developer ID Application: Release Test (TEAM)"
OTHER_IDENTITY = "Developer ID Application: Release Test (OTHER)"
TIMESTAMP = "2026-07-13T12:00:00Z"

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


def clean_env() -> dict[str, str]:
    env = dict(os.environ)
    for key in (
        "NMH_DEVELOPER_ID_APPLICATION",
        "NMH_NOTARY_PROFILE",
        "NMH_RELEASE_UAT_EVIDENCE",
        "NMH_VERSION_FILE",
        "NMH_BUNDLE_ID_FILE",
        "NMH_PACKAGE_FILE",
        "NMH_RELEASE_ARCHITECTURES_FILE",
        "NMH_SPARKLE_PUBLIC_ED_KEY",
        "NMH_SPARKLE_PUBLIC_ED_KEY_FILE",
        "NMH_BUNDLE_ID",
        "NMH_APP_NAME",
        "NMH_MARKETING_VERSION",
        "NMH_BUILD_VERSION",
        "NMH_SOURCE_COMMIT",
        "NMH_BUILD_ID",
        "NMH_BUILD_CONFIGURATION",
        "NMH_MIN_SYSTEM_VERSION",
        "NMH_DIST_DIR",
        "NMH_RELEASE_TEST_MODE",
    ):
        env.pop(key, None)
    return env


def run_bash_fn(fn: str, args: list[str], env_extra: dict[str, str] | None = None):
    env = clean_env()
    if env_extra:
        env.update(env_extra)
    quoted = " ".join(shlex.quote(a) for a in args)
    script = (
        f'set -euo pipefail; source "{RELEASE_ENV}"; source "{SNAPSHOT_LIB}"; '
        f"{fn} {quoted}".strip()
    )
    return subprocess.run(
        ["bash", "-c", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def run_cmd(args: list[str], env_extra: dict[str, str] | None = None):
    env = clean_env()
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env
    )


def sha_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(repo: pathlib.Path, *args: str) -> str:
    result = run_cmd(["git", "-C", str(repo)] + list(args))
    assert result.returncode == 0, f"git {args} failed: {result.stderr}"
    return result.stdout.strip()


def init_fixture_repo(base: pathlib.Path) -> pathlib.Path:
    repo = base / "fixture-source"
    repo.mkdir(parents=True)
    run_cmd(["git", "-C", str(repo), "init", "-q"])
    run_cmd(["git", "-C", str(repo), "config", "user.name", "Provenance Test"])
    run_cmd(["git", "-C", str(repo), "config", "user.email", "prov-test@example.invalid"])
    (repo / "VERSION").write_text(REAL_VERSION + "\n", encoding="utf-8")
    (repo / "BUNDLE_ID").write_text(REAL_BUNDLE_ID + "\n", encoding="utf-8")
    (repo / "RELEASE_ARCHITECTURES").write_text("arm64\n", encoding="utf-8")
    (repo / "Package.swift").write_text(
        '// swift-tools-version: 6.0\nimport PackageDescription\n'
        'let package = Package(name: "Fixture", platforms: [.macOS("14.2")], products: [], targets: [])\n',
        encoding="utf-8",
    )
    (repo / "SPARKLE_PUBLIC_ED_KEY").write_text(REAL_SNAPSHOT_KEY + "\n", encoding="utf-8")
    (repo / "README.md").write_text("fixture\n", encoding="utf-8")
    # Strict validators resolve --commit against their own repository root
    # (NMH_RELEASE_ROOT derived from BASH_SOURCE). The fixture-only commit does
    # not exist in the real ROOT tree, so copy the actual validator files
    # byte-identical into the fixture before its commit and invoke validators
    # from the fixture. No gate is weakened; the pinned SHA still proves
    # exact fixture provenance.
    for rel in (
        "script/validate-release-uat.sh",
        "script/validate-release-approval.sh",
        "script/release-env.sh",
        "script/lib/release_gates.sh",
        "script/lib/release_uat.py",
    ):
        src = ROOT / rel
        assert src.is_file(), f"real tree missing {rel}"
        dst = repo / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(src), str(dst))
    for rel in (
        "script/validate-release-uat.sh",
        "script/validate-release-approval.sh",
        "script/release-env.sh",
    ):
        (repo / rel).chmod(0o755)
    run_cmd(["git", "-C", str(repo), "add", "."])
    run_cmd(["git", "-C", str(repo), "commit", "-qm", "pinned"])
    return repo


def write_valid_uat(path: pathlib.Path, commit: str, build_id: str) -> None:
    payload = {
        "schema_version": 1,
        "version": REAL_VERSION,
        "commit": commit,
        "bundle_id": REAL_BUNDLE_ID,
        "status": "approved",
        "approved_by": "Release Test",
        "approved_at_utc": TIMESTAMP,
        "machine": "arm64 macOS test machine",
        "tested_build": {
            "build_id": build_id,
            "build_configuration": "release",
            "signing_identity": TEST_IDENTITY,
            "hardened_runtime": True,
        },
        "checks": {name: "passed" for name in REQUIRED_CHECKS},
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def mutate_json(path: pathlib.Path, fn) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    fn(payload)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def generate_manifest(output: pathlib.Path, artifact_name: str, artifact_sha: str, size: int, commit: str, build_id: str) -> None:
    result = run_cmd(
        [
            sys.executable,
            str(GENERATOR),
            "manifest",
            "--output",
            str(output),
            "--version",
            REAL_VERSION,
            "--bundle-id",
            REAL_BUNDLE_ID,
            "--tag",
            f"v{REAL_VERSION}",
            "--commit",
            commit,
            "--build-id",
            build_id,
            "--build-number",
            "1",
            "--architectures",
            "arm64",
            "--minimum-macos",
            "14.2",
            "--artifact",
            artifact_name,
            "--artifact-size",
            str(size),
            "--artifact-sha256",
            artifact_sha,
            "--created-utc",
            TIMESTAMP,
            "--signing-identity",
            TEST_IDENTITY,
            "--validation-status",
            "passed",
            "--public-release",
        ]
    )
    assert result.returncode == 0, f"manifest generator failed: {result.stderr}"


def generate_approval(output: pathlib.Path, artifact_name: str, artifact_sha: str, manifest: pathlib.Path, uat: pathlib.Path, commit: str) -> None:
    gates = [
        "clean-tagged-checkout|./script/release-preflight.sh|passed|" + TIMESTAMP,
        "consolidated-mac-uat|./script/validate-release-uat.sh|passed|" + TIMESTAMP,
        "debug-ci|./script/ci.sh|passed|" + TIMESTAMP,
        "user-e2e|NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh|passed|" + TIMESTAMP,
        "release-configuration|./script/ci-release.sh|passed|" + TIMESTAMP,
        "thread-sanitizer|./script/ci-tsan.sh|passed|" + TIMESTAMP,
        "release-identity|./script/release-version-verify.sh|passed|" + TIMESTAMP,
        "release-platform-contract|RELEASE_ARCHITECTURES,Package.swift minimum macOS|passed|" + TIMESTAMP,
        "public-tree-hygiene|./script/public-tree-hygiene.sh --public-release|passed|" + TIMESTAMP,
        "sign-notarize-staple|codesign, notarytool, stapler, spctl|passed|" + TIMESTAMP,
        "artifact-validation|./script/validate-release-artifact.sh|passed|" + TIMESTAMP,
        "update-feed|./script/validate-update-feed.py|passed|" + TIMESTAMP,
    ]
    args = [
        sys.executable,
        str(GENERATOR),
        "approval",
        "--output",
        str(output),
        "--version",
        REAL_VERSION,
        "--bundle-id",
        REAL_BUNDLE_ID,
        "--tag",
        f"v{REAL_VERSION}",
        "--commit",
        commit,
        "--artifact",
        artifact_name,
        "--artifact-sha256",
        artifact_sha,
        "--manifest",
        manifest.name,
        "--manifest-sha256",
        sha_file(manifest),
        "--machine",
        "arm64 macOS test machine",
        "--created-utc",
        TIMESTAMP,
        "--uat-file",
        uat.name,
        "--uat-sha256",
        sha_file(uat),
        "--uat-approved-by",
        "Release Test",
        "--uat-approved-at-utc",
        TIMESTAMP,
    ]
    for gate in gates:
        args += ["--gate", gate]
    result = run_cmd(args)
    assert result.returncode == 0, f"approval generator failed: {result.stderr}"


class PipelineProvenanceTests(unittest.TestCase):
    def test_pinned_snapshot_ignores_concurrent_live_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            repo = init_fixture_repo(base)
            pinned = git(repo, "rev-parse", "HEAD")
            release_dir = base / "dist" / "release"
            release_dir.mkdir(parents=True)
            short = git(repo, "rev-parse", "--short=12", "HEAD")

            init_result = run_bash_fn("nmh_snapshot_init_run_dir", [str(release_dir), short])
            self.assertEqual(init_result.returncode, 0, msg=init_result.stderr)
            run_dir = pathlib.Path(init_result.stdout.strip())
            self.addCleanup(shutil.rmtree, run_dir, True)
            self.assertTrue(str(run_dir).startswith(str(release_dir)))

            create = run_bash_fn("nmh_snapshot_create_pinned_source", [str(repo), pinned, str(run_dir)])
            self.assertEqual(create.returncode, 0, msg=create.stderr)
            snapshot = pathlib.Path(create.stdout.strip())
            self.assertTrue((snapshot / "VERSION").is_file())
            self.assertTrue((run_dir / "snapshot-provenance.json").is_file())

            # Mutate the invoking source AFTER pinning/snapshot (concurrent change).
            (repo / "VERSION").write_text("0.0.0-evil\n", encoding="utf-8")
            (repo / "untracked-evil.txt").write_text("evil\n", encoding="utf-8")

            # Snapshot still carries pinned bytes, not live mutation.
            self.assertEqual((snapshot / "VERSION").read_text(encoding="utf-8").strip(), REAL_VERSION)
            pinned_version = run_cmd(["git", "-C", str(repo), "show", f"{pinned}:VERSION"]).stdout.strip()
            self.assertEqual((snapshot / "VERSION").read_text(encoding="utf-8").strip(), pinned_version)
            record = json.loads((run_dir / "snapshot-provenance.json").read_text(encoding="utf-8"))
            self.assertEqual(record["pinned_commit"], pinned)

            # Isolated .build: snapshot build dir differs from invoking checkout.
            self.assertNotEqual(str((snapshot / ".build").resolve()), str((ROOT / ".build").resolve()))

            # Cleanup is safe/bounded and preserves working tree/untracked content.
            cleanup = run_bash_fn("nmh_snapshot_cleanup", [str(run_dir), str(run_dir.parent)])
            self.assertEqual(cleanup.returncode, 0, msg=cleanup.stderr)
            self.assertFalse(run_dir.exists())
            self.assertTrue((repo / "VERSION").is_file())
            self.assertTrue((repo / "untracked-evil.txt").is_file())
            self.assertEqual((repo / "VERSION").read_text(encoding="utf-8").strip(), "0.0.0-evil")

    def test_snapshot_survives_release_output_removal(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            repo = init_fixture_repo(base)
            pinned = git(repo, "rev-parse", "HEAD")
            release_dir = base / "dist" / "release"
            release_dir.mkdir(parents=True)
            (release_dir / "old-output.txt").write_text("old\n", encoding="utf-8")
            short = git(repo, "rev-parse", "--short=12", "HEAD")
            init_result = run_bash_fn("nmh_snapshot_init_run_dir", [str(release_dir), short])
            self.assertEqual(init_result.returncode, 0, msg=init_result.stderr)
            run_dir = pathlib.Path(init_result.stdout.strip())
            self.addCleanup(shutil.rmtree, run_dir, True)
            create = run_bash_fn("nmh_snapshot_create_pinned_source", [str(repo), pinned, str(run_dir)])
            self.assertEqual(create.returncode, 0, msg=create.stderr)
            snapshot = pathlib.Path(create.stdout.strip())
            self.assertTrue((snapshot / "BUNDLE_ID").is_file())
            # Later `rm -rf "$RELEASE_DIR"` must not remove the sibling snapshot.
            shutil.rmtree(release_dir)
            self.assertFalse(release_dir.exists())
            self.assertTrue((snapshot / "BUNDLE_ID").is_file())
            self.assertEqual((snapshot / "BUNDLE_ID").read_text(encoding="utf-8").strip(), REAL_BUNDLE_ID)

    def test_frozen_uat_uses_frozen_bytes_after_original_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            repo = init_fixture_repo(base)
            pinned = git(repo, "rev-parse", "HEAD")
            build_id = f"{REAL_VERSION}+{pinned[:12]}"
            original = base / "original-uat.json"
            write_valid_uat(original, pinned, build_id)
            run_dir = base / "run"
            run_dir.mkdir()
            self.addCleanup(shutil.rmtree, run_dir, True)

            freeze = run_bash_fn("nmh_snapshot_freeze_uat", [str(original), str(run_dir)])
            self.assertEqual(freeze.returncode, 0, msg=freeze.stderr)
            frozen = pathlib.Path(freeze.stdout.strip())
            frozen_sha_before = sha_file(frozen)

            # Mutate the external original AFTER freezing.
            mutate_json(original, lambda p: p["checks"].__setitem__("privacy_permissions", "pending"))
            mutate_json(original, lambda p: p.__setitem__("commit", "0" * 40))
            self.assertNotEqual(sha_file(original), frozen_sha_before)

            # Frozen bytes are unchanged and still validate with the pinned API.
            # Invoke the fixture-copy validator so the fixture-only commit
            # resolves in the validator's own repository.
            self.assertEqual(sha_file(frozen), frozen_sha_before)
            fixture_uat_validator = repo / "script" / "validate-release-uat.sh"
            self.assertTrue(fixture_uat_validator.is_file())
            valid = run_cmd(
                [
                    "bash",
                    str(fixture_uat_validator),
                    "--evidence",
                    str(frozen),
                    "--commit",
                    pinned,
                    "--expected-build-id",
                    build_id,
                    "--expected-signing-identity",
                    TEST_IDENTITY,
                ]
            )
            self.assertEqual(valid.returncode, 0, msg=valid.stderr)
            self.assertIn("release UAT evidence ok", valid.stdout)

    def test_final_validation_rejects_bad_captured_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            repo = init_fixture_repo(base)
            pinned = git(repo, "rev-parse", "HEAD")
            build_id = f"{REAL_VERSION}+{pinned[:12]}"
            run_dir = base / "run"
            run_dir.mkdir()
            self.addCleanup(shutil.rmtree, run_dir, True)

            artifact = base / f"NikoMusicHub-{REAL_VERSION}.dmg"
            artifact.write_bytes(b"pipeline-fixture-artifact")
            artifact_sha = sha_file(artifact)
            manifest = base / f"NikoMusicHub-{REAL_VERSION}-manifest.json"
            generate_manifest(manifest, artifact.name, artifact_sha, artifact.stat().st_size, pinned, build_id)
            original = base / "uat.json"
            write_valid_uat(original, pinned, build_id)
            freeze = run_bash_fn("nmh_snapshot_freeze_uat", [str(original), str(run_dir)])
            self.assertEqual(freeze.returncode, 0, msg=freeze.stderr)
            frozen = pathlib.Path(freeze.stdout.strip())
            approval = base / "approval.json"
            generate_approval(approval, artifact.name, artifact_sha, manifest, frozen, pinned)

            # Invoke the fixture-copy validator so the fixture-only commit
            # resolves in the validator's own repository.
            fixture_approval_validator = repo / "script" / "validate-release-approval.sh"
            self.assertTrue(fixture_approval_validator.is_file())
            good = run_cmd(
                [
                    "bash",
                    str(fixture_approval_validator),
                    "--approval",
                    str(approval),
                    "--artifact",
                    str(artifact),
                    "--manifest",
                    str(manifest),
                    "--uat",
                    str(frozen),
                    "--commit",
                    pinned,
                    "--expected-build-id",
                    build_id,
                    "--expected-signing-identity",
                    TEST_IDENTITY,
                ]
            )
            self.assertEqual(good.returncode, 0, msg=good.stderr)

            # Capture bad evidence then rehash the approval so hashes match: the
            # final validator must still reject for semantics, not the hash.
            mutate_json(frozen, lambda p: p["checks"].__setitem__("privacy_permissions", "pending"))
            generate_approval(approval, artifact.name, artifact_sha, manifest, frozen, pinned)
            bad = run_cmd(
                [
                    "bash",
                    str(fixture_approval_validator),
                    "--approval",
                    str(approval),
                    "--artifact",
                    str(artifact),
                    "--manifest",
                    str(manifest),
                    "--uat",
                    str(frozen),
                    "--commit",
                    pinned,
                    "--expected-build-id",
                    build_id,
                    "--expected-signing-identity",
                    TEST_IDENTITY,
                ]
            )
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("must be passed", bad.stderr)
            self.assertNotIn("identity mismatch", bad.stderr)

    def test_public_key_override_rejects_before_publication(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            repo = init_fixture_repo(base)
            pinned = git(repo, "rev-parse", "HEAD")
            run_dir = base / "run"
            run_dir.mkdir()
            self.addCleanup(shutil.rmtree, run_dir, True)
            create = run_bash_fn("nmh_snapshot_create_pinned_source", [str(repo), pinned, str(run_dir)])
            self.assertEqual(create.returncode, 0, msg=create.stderr)
            snapshot = pathlib.Path(create.stdout.strip())

            # Stubbed publication side effect that must never be reached.
            stub_bin = base / "stub-bin"
            stub_bin.mkdir()
            marker = base / "gh-was-called"
            (stub_bin / "gh").write_text(f"#!/usr/bin/env bash\ntouch {shlex.quote(str(marker))}\nexit 0\n", encoding="utf-8")
            (stub_bin / "gh").chmod(0o755)

            # Production silently accepting an env alternate is forbidden.
            rejected = run_bash_fn(
                "nmh_snapshot_reject_public_overrides",
                ["public"],
                env_extra={"NMH_SPARKLE_PUBLIC_ED_KEY": ALT_KEY},
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("NMH_SPARKLE_PUBLIC_ED_KEY", rejected.stderr)

            rejected_file = run_bash_fn(
                "nmh_snapshot_reject_public_overrides",
                ["public"],
                env_extra={"NMH_SPARKLE_PUBLIC_ED_KEY_FILE": "/tmp/alt-key"},
            )
            self.assertNotEqual(rejected_file.returncode, 0)
            self.assertIn("NMH_SPARKLE_PUBLIC_ED_KEY_FILE", rejected_file.stderr)

            # Local/test use keeps the explicit override.
            allowed = run_bash_fn(
                "nmh_snapshot_reject_public_overrides",
                ["local-only"],
                env_extra={"NMH_SPARKLE_PUBLIC_ED_KEY": ALT_KEY},
            )
            self.assertEqual(allowed.returncode, 0, msg=allowed.stderr)

            # Resolved-vs-pinned mismatch rejects before any build/publish step.
            mismatch = run_bash_fn("nmh_snapshot_verify_sparkle_continuity", [str(snapshot), ALT_KEY])
            self.assertNotEqual(mismatch.returncode, 0)
            self.assertIn("mismatch", mismatch.stderr)
            self.assertFalse(marker.exists())

            # Pinned continuity passes with the repository key.
            ok = run_bash_fn("nmh_snapshot_verify_sparkle_continuity", [str(snapshot), REAL_SNAPSHOT_KEY])
            self.assertEqual(ok.returncode, 0, msg=ok.stderr)

    def test_source_override_rejection_preserves_local_use(self) -> None:
        rejected = run_bash_fn(
            "nmh_snapshot_reject_public_overrides",
            ["public"],
            env_extra={"NMH_VERSION_FILE": "/tmp/evil-VERSION"},
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("NMH_VERSION_FILE", rejected.stderr)

        rejected_bundle = run_bash_fn(
            "nmh_snapshot_reject_public_overrides",
            ["public"],
            env_extra={"NMH_BUNDLE_ID_FILE": "/tmp/evil-BUNDLE_ID"},
        )
        self.assertNotEqual(rejected_bundle.returncode, 0)
        self.assertIn("NMH_BUNDLE_ID_FILE", rejected_bundle.stderr)

        # Dev/local/test use is preserved: same envs pass outside public mode.
        allowed = run_bash_fn(
            "nmh_snapshot_reject_public_overrides",
            ["local-only"],
            env_extra={"NMH_VERSION_FILE": "/tmp/evil-VERSION"},
        )
        self.assertEqual(allowed.returncode, 0, msg=allowed.stderr)

        # Public product builds must never use the test stub bundle hook.
        rejected_hook = run_bash_fn(
            "nmh_snapshot_reject_public_overrides",
            ["public"],
            env_extra={"NMH_RELEASE_TEST_MODE": "1"},
        )
        self.assertNotEqual(rejected_hook.returncode, 0)
        self.assertIn("NMH_RELEASE_TEST_MODE", rejected_hook.stderr)

        # Local-only and dev/test wrappers keep the explicit hook.
        allowed_hook = run_bash_fn(
            "nmh_snapshot_reject_public_overrides",
            ["local-only"],
            env_extra={"NMH_RELEASE_TEST_MODE": "1"},
        )
        self.assertEqual(allowed_hook.returncode, 0, msg=allowed_hook.stderr)

    def test_cleanup_is_safe_and_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            repo = init_fixture_repo(base)
            pinned = git(repo, "rev-parse", "HEAD")
            release_dir = base / "dist" / "release"
            release_dir.mkdir(parents=True)
            short = git(repo, "rev-parse", "--short=12", "HEAD")
            init_result = run_bash_fn("nmh_snapshot_init_run_dir", [str(release_dir), short])
            self.assertEqual(init_result.returncode, 0, msg=init_result.stderr)
            run_dir = pathlib.Path(init_result.stdout.strip())
            self.addCleanup(shutil.rmtree, run_dir, True)
            create = run_bash_fn("nmh_snapshot_create_pinned_source", [str(repo), pinned, str(run_dir)])
            self.assertEqual(create.returncode, 0, msg=create.stderr)

            # Refuses the parent itself.
            refuse_parent = run_bash_fn("nmh_snapshot_cleanup", [str(run_dir.parent), str(run_dir.parent)])
            self.assertNotEqual(refuse_parent.returncode, 0)
            self.assertTrue(run_dir.exists())

            # Refuses a dir outside the allowed parent.
            outside = base / "outside"
            outside.mkdir()
            refuse_outside = run_bash_fn("nmh_snapshot_cleanup", [str(run_dir), str(outside)])
            self.assertNotEqual(refuse_outside.returncode, 0)
            self.assertTrue(run_dir.exists())

            # Refuses a non-provenance dir even under the parent.
            impostor = run_dir.parent / "not-provenance-dir"
            impostor.mkdir()
            refuse_impostor = run_bash_fn("nmh_snapshot_cleanup", [str(impostor), str(run_dir.parent)])
            self.assertNotEqual(refuse_impostor.returncode, 0)
            self.assertTrue(impostor.is_dir())

            # Valid cleanup removes only the run dir and preserves artifacts definition.
            ok = run_bash_fn("nmh_snapshot_cleanup", [str(run_dir), str(run_dir.parent)])
            self.assertEqual(ok.returncode, 0, msg=ok.stderr)
            self.assertFalse(run_dir.exists())
            self.assertTrue(release_dir.is_dir())


class PipelineOrchestrationTests(unittest.TestCase):
    """Behavioral orchestration: run the actual release-all.sh in a fixture.

    Each fixture is a disposable tiny Git repo containing the actual current
    release scripts (byte-identical copies of the real tree for release-all,
    release-env, and release_snapshot) plus fixture-only stubs for heavy
    stages (ci/e2e/release/tsan), feed tooling, PATH doubles for
    network/signing/bundle tools, and a committed fixture-only
    app_lifecycle build stub. No new production bypass env is introduced:
    the production non-TEST_MODE branch is invoked (NMH_RELEASE_TEST_MODE is
    never set; public mode refuses it); the fixture lifecycle stub keeps the
    real source-time checks (NMH_ROOT_DIR derived from BASH_SOURCE, dist
    beneath <snapshot>/dist) and only fakes the heavy Swift compile/sign so
    the pinned build still writes the private snapshot dist with pinned
    metadata. All other stubs live solely in fixture PATH/scripts (temp
    dirs, never in the production tree) and the tests assert real
    signing/network are never touched.

    Covers the unmet requirement: actual release-all orchestration (not just
    isolated helper functions):
    - R1 live VERSION/HEAD/source mutation after snapshot/gate start still
      yields pinned gates/build/metadata/validators and no live .build; the
      real lifecycle dist/root checks run against the pinned snapshot
      (snapshot_root/dist logged from the actual sourced pipeline).
    - R2 original-UAT mutation after validation still approves retained
      frozen bytes; FINAL drift from FROZEN fails closed (hash) and bad
      semantics fail closed (validator) rather than silently re-approving;
      the frozen digest captured before validation is unchanged after.
    - R4 public-key override and public TEST_MODE hook reject before
      publication; missing credentials fail nonzero with bounded cleanup.
    """

    def assert_no_production_stubs(self) -> None:
        for rel in ("script/ci.sh", "script/e2e_user_smoke.sh", "script/release-all.sh",
                    "script/release-env.sh", "script/lib/release_snapshot.sh",
                    "script/lib/app_lifecycle.sh"):
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
            self.assertNotIn("NMH_ORCH_", text, msg=f"production {rel} must not contain test-only stubs")
            self.assertNotIn("FIXTURE-ONLY BUILD STUB", text, msg=f"production {rel} must not contain fixture build stub")

    def assert_actual_scripts_copied(self, fixture: pathlib.Path) -> None:
        for rel in ("script/release-all.sh", "script/release-env.sh", "script/lib/release_snapshot.sh"):
            real = ROOT / rel
            copied = fixture / rel
            self.assertTrue(copied.is_file(), msg=f"fixture missing {rel}")
            self.assertEqual(
                hashlib.sha256(real.read_bytes()).hexdigest(),
                hashlib.sha256(copied.read_bytes()).hexdigest(),
                msg=f"fixture {rel} must be byte-identical to actual current script",
            )

    def build_fixture(self, base: pathlib.Path) -> dict:
        """Create tiny git fixture with actual scripts + fixture-only stubs."""
        self.assert_no_production_stubs()
        fixture = base.resolve() / "orch-fixture"
        fixture.mkdir(parents=True)
        run_cmd(["git", "-C", str(fixture), "init", "-q"])
        run_cmd(["git", "-C", str(fixture), "config", "user.name", "Orch Test"])
        run_cmd(["git", "-C", str(fixture), "config", "user.email", "orch-test@example.invalid"])
        # Actual current release scripts + canonical files (copied, never invented).
        # .gitignore is genuine production hygiene: it keeps private dist/ and
        # .build/ untracked so public preflight/clean checks stay green.
        real_files = [
            ".gitignore",
            "VERSION",
            "BUNDLE_ID",
            "RELEASE_ARCHITECTURES",
            "Package.swift",
            "SPARKLE_PUBLIC_ED_KEY",
            "CHANGELOG.md",
            "SBOM.spdx.json",
            "Package.resolved",
            "THIRD_PARTY_NOTICES.md",
            "SOURCE_PROVENANCE.md",
            "LICENSE",
            "script/release-version-allowlist.txt",
            "script/release-all.sh",
            "script/release-env.sh",
            "script/release-preflight.sh",
            "script/release-version-verify.sh",
            "script/validate-release-uat.sh",
            "script/validate-release-approval.sh",
            "script/validate-release-artifact.sh",
            "script/public-tree-hygiene.sh",
            "script/generate-release-record.py",
            "script/extract-release-notes.sh",
            "script/validate-release-metadata.py",
            "script/lib/release_snapshot.sh",
            "script/lib/release_gates.sh",
            "script/lib/app_lifecycle.sh",
            "script/lib/release_uat.py",
        ]
        for rel in real_files:
            src = ROOT / rel
            self.assertTrue(src.is_file(), msg=f"real tree missing {rel}")
            dst = fixture / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(src), str(dst))
        # Make scripts executable (copied mode may lose +x on some filesystems).
        for rel in [
            "script/release-all.sh",
            "script/release-env.sh",
            "script/release-preflight.sh",
            "script/release-version-verify.sh",
            "script/validate-release-uat.sh",
            "script/validate-release-approval.sh",
            "script/validate-release-artifact.sh",
            "script/public-tree-hygiene.sh",
            "script/generate-release-record.py",
            "script/extract-release-notes.sh",
            "script/validate-release-metadata.py",
        ]:
            (fixture / rel).chmod(0o755)
        # Fixture-only gate stubs (committed only inside fixture, never production).
        (fixture / "script" / "ci.sh").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'snap_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n'
            '# Materialize the pinned .build tool from the tracked normal-path stub\n'
            '# source only during the stub gate. The .build output itself stays\n'
            '# untracked/ignored (genuine .gitignore) so real public-tree hygiene\n'
            '# (git ls-files) never sees build output. Do not weaken real hygiene.\n'
            'stub_src="$snap_root/script/fixture-generate-appcast-stub.sh"\n'
            'dst="$snap_root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"\n'
            'if [[ -f "$stub_src" && ! -x "$dst" ]]; then\n'
            '  mkdir -p "$(dirname "$dst")"\n'
            '  cp "$stub_src" "$dst"\n'
            '  chmod +x "$dst"\n'
            'fi\n'
            'echo "gate-ci snapshot_root=$snap_root" >>"${NMH_ORCH_GATE_LOG:?}"\n'
            'git -C "$snap_root" rev-parse HEAD >>"${NMH_ORCH_GATE_LOG:?}"\n'
            'cat "$snap_root/VERSION" >>"${NMH_ORCH_GATE_LOG:?}"\n'
            'mode="${NMH_ORCH_MUTATE_MODE:-none}"\n'
            'if [[ "$mode" == "live-version-and-head" ]]; then\n'
            '  printf \'0.0.0-evil\\n\' >"${NMH_ORCH_LIVE_ROOT:?}/VERSION"\n'
            '  printf \'evil\\n\' >"${NMH_ORCH_LIVE_ROOT}/untracked-evil.txt"\n'
            '  git -C "$NMH_ORCH_LIVE_ROOT" commit --allow-empty -qm "evil head move"\n'
            '  printf \'# evil concurrent source mutation\\n\' >>"${NMH_ORCH_LIVE_ROOT}/script/release-env.sh"\n'
            '  printf \'# evil concurrent orchestrator mutation\\n\' >>"${NMH_ORCH_LIVE_ROOT}/script/release-all.sh"\n'
            '  printf \'# evil concurrent lifecycle mutation\\n\' >>"${NMH_ORCH_LIVE_ROOT}/script/lib/app_lifecycle.sh"\n'
            'elif [[ "$mode" == "original-uat" ]]; then\n'
            '  /usr/bin/python3 - "${NMH_ORCH_ORIGINAL_UAT:?}" <<\'PY\'\n'
            'import json, pathlib, sys\n'
            'p = pathlib.Path(sys.argv[1])\n'
            'd = json.loads(p.read_text())\n'
            'd["commit"] = "0"*40\n'
            'd["checks"]["privacy_permissions"] = "pending"\n'
            'p.write_text(json.dumps(d, indent=2, sort_keys=True)+"\\n")\n'
            'PY\n'
            'elif [[ "$mode" == "final-uat-bad" ]]; then\n'
            '  live="${NMH_ORCH_LIVE_ROOT:?}"\n'
            '  for f in "$live"/dist/release/*-uat.json; do\n'
            '    [[ -f "$f" ]] || continue\n'
            '    /usr/bin/python3 - "$f" <<\'PY\'\n'
            'import json, pathlib, sys\n'
            'p = pathlib.Path(sys.argv[1])\n'
            'd = json.loads(p.read_text())\n'
            'd["checks"]["privacy_permissions"] = "pending"\n'
            'p.write_text(json.dumps(d, indent=2, sort_keys=True)+"\\n")\n'
            'PY\n'
            '    echo "mutated-final-uat=$f" >>"${NMH_ORCH_GATE_LOG:?}"\n'
            '  done\n'
            'fi\n'
            'exit 0\n',
            encoding="utf-8",
        )
        for name in ("e2e_user_smoke.sh", "ci-release.sh", "ci-tsan.sh"):
            (fixture / "script" / name).write_text(
                '#!/usr/bin/env bash\nset -euo pipefail\n'
                'snap_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n'
                f'echo "gate-{name} snapshot_root=$snap_root" >>"${{NMH_ORCH_GATE_LOG:?}}"\n'
                'exit 0\n',
                encoding="utf-8",
            )
        for name in ("ci.sh", "e2e_user_smoke.sh", "ci-release.sh", "ci-tsan.sh"):
            (fixture / "script" / name).chmod(0o755)
        # Fixture-only feed validator stub (test-mode bundle lacks SU keys;
        # real validator is proven by Tests/test_release_scripts.sh feed cases).
        (fixture / "script" / "validate-update-feed.py").write_text(
            '#!/usr/bin/env python3\nimport os, sys, pathlib\n'
            'log = pathlib.Path(os.environ.get("NMH_ORCH_GATE_LOG", "/tmp/nonexistent-orch-gate.log"))\n'
            'try:\n'
            '  log.parent.mkdir(parents=True, exist_ok=True)\n'
            '  log.open("a").write(f"validate-update-feed-stub argv={sys.argv[1:]}\\n")\n'
            'except Exception:\n'
            '  pass\n'
            'print("update feed validated (fixture stub)")\n',
            encoding="utf-8",
        )
        (fixture / "script" / "validate-update-feed.py").chmod(0o755)
        # Fixture-only generate_appcast stub source in the normal tracked test path
        # (script/, never .build/). The pinned snapshot .build copy is materialized
        # only during the stub gate above, so genuine .gitignore keeps it untracked
        # and real public-tree hygiene (git ls-files) stays green.
        (fixture / "script" / "fixture-generate-appcast-stub.sh").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "generate_appcast $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'out=""\nprev=""\nfor arg in "$@"; do\n'
            '  if [[ "$prev" == "-o" ]]; then out="$arg"; fi\n'
            '  prev="$arg"\n'
            'done\n'
            '[[ -n "$out" ]] || { echo "generate_appcast stub: missing -o" >&2; exit 1; }\n'
            'mkdir -p "$(dirname "$out")"\n'
            'printf \'<rss version="2.0"><channel><title>Fixture</title></channel></rss>\\n\' >"$out"\n',
            encoding="utf-8",
        )
        (fixture / "script" / "fixture-generate-appcast-stub.sh").chmod(0o755)
        # Fixture-only app_lifecycle build stub (committed only inside fixture,
        # never production): the real file prefix above already ran its
        # source-time checks (NMH_ROOT_DIR from BASH_SOURCE, NMH_DIST_DIR
        # beneath <snapshot>/dist, bundle-id). Only the heavy Swift
        # compile/sign is faked so the production non-TEST_MODE branch can run
        # hermetically; it still writes the private snapshot dist with pinned
        # metadata and logs the actual sourced snapshot root/dist for
        # assertions. No new public escape hook is introduced.
        with (fixture / "script" / "lib" / "app_lifecycle.sh").open("a", encoding="utf-8") as handle:
            handle.write(
                '\n# FIXTURE-ONLY BUILD STUB (never in production).\n'
                '# Real lifecycle checks above have already run; reaching here proves\n'
                '# NMH_DIST_DIR is beneath the pinned snapshot dist.\n'
                'nmh_build_bundle() {\n'
                '  /usr/bin/shasum -a 256 "${BASH_SOURCE[0]}" >>"${NMH_ORCH_GATE_LOG:?}.lifecycle-sha"\n'
                '  echo "fixture-build snapshot_root=$NMH_ROOT_DIR dist=$NMH_DIST_DIR source=${BASH_SOURCE[0]}" >>"${NMH_ORCH_GATE_LOG:?}"\n'
                '  case "$NMH_DIST_DIR" in\n'
                '    "$NMH_ROOT_DIR"/dist/*) ;;\n'
                '    *) echo "fixture-build: dist not beneath snapshot dist: $NMH_DIST_DIR not under $NMH_ROOT_DIR/dist" >&2; return 1 ;;\n'
                '  esac\n'
                '  case "$NMH_ROOT_DIR" in\n'
                '    *pinned-source*) ;;\n'
                '    *) echo "fixture-build: root is not the pinned snapshot: $NMH_ROOT_DIR" >&2; return 1 ;;\n'
                '  esac\n'
                '  local app="$NMH_DIST_DIR/$NMH_APP_NAME.app"\n'
                '  rm -rf "$app"\n'
                '  mkdir -p "$app/Contents/MacOS"\n'
                '  printf \'#!/usr/bin/env bash\\necho NikoMusicHub %s\\n\' "$NMH_BUILD_ID" >"$app/Contents/MacOS/$NMH_APP_NAME"\n'
                '  chmod +x "$app/Contents/MacOS/$NMH_APP_NAME"\n'
                '  cat >"$app/Contents/Info.plist" <<PLIST\n'
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                '<plist version="1.0"><dict>\n'
                '  <key>CFBundleExecutable</key><string>NikoMusicHub</string>\n'
                '  <key>CFBundleIdentifier</key><string>$NMH_BUNDLE_ID</string>\n'
                '  <key>CFBundleName</key><string>Niko Music Hub</string>\n'
                '  <key>CFBundlePackageType</key><string>APPL</string>\n'
                '  <key>CFBundleShortVersionString</key><string>$NMH_MARKETING_VERSION</string>\n'
                '  <key>CFBundleVersion</key><string>$NMH_BUILD_VERSION</string>\n'
                '  <key>NMHBuildID</key><string>$NMH_BUILD_ID</string>\n'
                '  <key>NMHBuildConfiguration</key><string>$NMH_BUILD_CONFIGURATION</string>\n'
                '  <key>NMHSourceCommit</key><string>$NMH_SOURCE_COMMIT</string>\n'
                '  <key>LSMinimumSystemVersion</key><string>$NMH_MIN_SYSTEM_VERSION</string>\n'
                '</dict></plist>\n'
                'PLIST\n'
                '}\n'
            )
        run_cmd(["git", "-C", str(fixture), "add", "."])
        run_cmd(["git", "-C", str(fixture), "commit", "-qm", "fixture pinned"])
        # Second commit so build-number (rev-list count) is 2; live-feed stub returns 1.
        run_cmd(["git", "-C", str(fixture), "commit", "-q", "--allow-empty", "-m", "fixture second"])
        pinned = git(fixture, "rev-parse", "HEAD")
        # Bare origin so preflight ls-remote succeeds; dry-run allows missing tag.
        origin = base / "orch-origin.git"
        run_cmd(["git", "init", "-q", "--bare", str(origin)])
        run_cmd(["git", "-C", str(fixture), "remote", "add", "origin", str(origin)])
        self.assert_actual_scripts_copied(fixture)
        return {"fixture": fixture, "pinned": pinned, "origin": origin}

    def make_stub_bin(self, base: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path, pathlib.Path]:
        stub_bin = base / "stub-bin"
        stub_bin.mkdir(parents=True, exist_ok=True)
        gate_log = base / "gate.log"
        tool_log = base / "tool.log"
        gh_marker = base / "gh-was-called"
        gate_log.write_text("", encoding="utf-8")
        tool_log.write_text("", encoding="utf-8")
        (stub_bin / "hdiutil").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "hdiutil $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'if [[ "${1:-}" == "create" ]]; then\n'
            '  dmg="${@: -1}"\nmkdir -p "$(dirname "$dmg")"\n'
            '  printf \'fixture-dmg-bytes\' >"$dmg"\n  exit 0\nfi\n'
            'if [[ "${1:-}" == "attach" ]]; then\n'
            '  artifact="${2:-}"\n  mountpoint=""\n  prev=""\n'
            '  for arg in "$@"; do if [[ "$prev" == "-mountpoint" ]]; then mountpoint="$arg"; fi; prev="$arg"; done\n'
            '  [[ -n "$mountpoint" && -n "$artifact" ]] || { echo "hdiutil stub: missing mountpoint/artifact" >&2; exit 1; }\n'
            '  mkdir -p "$mountpoint"\n'
            '  dmg_dir="$(cd "$(dirname "$artifact")" && pwd)"\n'
            '  app="$dmg_dir/build/NikoMusicHub.app"\n'
            '  [[ -d "$app" ]] || { echo "hdiutil stub: built app missing at $app" >&2; exit 1; }\n'
            '  rm -rf "$mountpoint/NikoMusicHub.app"\n  cp -R "$app" "$mountpoint/NikoMusicHub.app"\n  exit 0\nfi\n'
            'if [[ "${1:-}" == "detach" ]]; then exit 0; fi\n'
            'echo "hdiutil stub: unhandled $*" >&2; exit 1\n',
            encoding="utf-8",
        )
        (stub_bin / "lipo").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "lipo $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'if [[ "${1:-}" == "-archs" ]]; then printf \'arm64\\n\'; exit 0; fi\n'
            'exit 0\n',
            encoding="utf-8",
        )
        (stub_bin / "codesign").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "codesign $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'if [[ "$*" == *"--entitlements"* ]]; then\n'
            '  target="${@: -1}"\n'
            '  if [[ "$target" == *"/NikoMusicHub.app" ]]; then\n'
            '    cat <<\'PLIST\'\n<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0"><dict>\n<key>com.apple.security.device.audio-input</key>\n<true/>\n</dict></plist>\nPLIST\n'
            '    exit 0\n  else\n    printf \'\'; exit 0\n  fi\nfi\n'
            'if [[ "$*" == *"-dvv"* || "$*" == *"-dv"* ]]; then\n'
            '  cat <<\'SIG\'\nExecutable=/fixture/NikoMusicHub\nIdentifier=com.niko96.NikoMusicHub\n'
            'Format=app bundle with Mach-O thin (arm64)\nCodeDirectory v=20400 size=12345 flags=0x10000(runtime) hashes=abc\n'
            'Authority=Developer ID Application: Release Test (TEAM)\nTimestamp=2026-07-13T12:00:00Z\nTeamIdentifier=TEAM\nRuntime Version=14.2.0\nSIG\n'
            '  exit 0\nfi\n'
            'exit 0\n',
            encoding="utf-8",
        )
        (stub_bin / "xcrun").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "xcrun $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'if [[ "${1:-}" == "--find" ]]; then printf \'/tmp/fixture-%s\\n\' "${2:-tool}"; exit 0; fi\n'
            'if [[ "$*" == *"notarytool history"* ]]; then exit 0; fi\n'
            'if [[ "$*" == *"notarytool submit"* ]]; then\n'
            '  for i in 1 2 3 4 5; do echo "  progress line $i"; done\n'
            '  echo "  id: 00000000-0000-0000-0000-000000000000"\n  echo "  status: Accepted"\n  exit 0\nfi\n'
            'if [[ "$*" == *"notarytool log"* ]]; then printf \'{"status":"Accepted"}\\n\'; exit 0; fi\n'
            'if [[ "$*" == *"stapler"* ]]; then exit 0; fi\n'
            'exit 0\n',
            encoding="utf-8",
        )
        (stub_bin / "spctl").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "spctl $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'exit 0\n',
            encoding="utf-8",
        )
        (stub_bin / "curl").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "curl $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'if [[ "$*" == *"--write-out"* ]]; then printf \'403\'; exit 0; fi\n'
            'cat <<\'FEED\'\n<?xml version="1.0" standalone="yes"?>'
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
            '<channel><title>NikoMusicHub</title>\n'
            '<item><title>0.0.1</title><sparkle:version>1</sparkle:version>'
            '<sparkle:shortVersionString>0.0.1</sparkle:shortVersionString></item>\n'
            '</channel></rss>\nFEED\n',
            encoding="utf-8",
        )
        (stub_bin / "swift").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "swift $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'if [[ "$*" == *"--version"* ]]; then echo "Swift version 6.99.0"; exit 0; fi\n'
            'exit 0\n',
            encoding="utf-8",
        )
        (stub_bin / "gh").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'echo "gh $*" >>"${NMH_ORCH_TOOL_LOG:?}"\n'
            'if [[ -n "${NMH_ORCH_GH_MARKER:-}" ]]; then touch "$NMH_ORCH_GH_MARKER"; fi\n'
            'exit 0\n',
            encoding="utf-8",
        )
        for name in ("hdiutil", "lipo", "codesign", "xcrun", "spctl", "curl", "swift", "gh"):
            (stub_bin / name).chmod(0o755)
        return stub_bin, gate_log, tool_log, gh_marker

    def orch_env(self, stub_bin: pathlib.Path, gate_log: pathlib.Path, tool_log: pathlib.Path,
                 gh_marker: pathlib.Path, fixture: pathlib.Path, extra: dict | None = None) -> dict:
        env = clean_env()
        env["PATH"] = f"{stub_bin}{os.pathsep}{env.get('PATH', '/usr/bin:/bin')}"
        # Production branch is invoked: NMH_RELEASE_TEST_MODE is never set here
        # (public mode refuses it; local-only production uses the fixture
        # lifecycle stub below, not the TEST_MODE shortcut).
        env.pop("NMH_RELEASE_TEST_MODE", None)
        env["NMH_RELEASE_DIR"] = str(fixture / "dist" / "release")
        env["NMH_ORCH_GATE_LOG"] = str(gate_log)
        env["NMH_ORCH_TOOL_LOG"] = str(tool_log)
        env["NMH_ORCH_GH_MARKER"] = str(gh_marker)
        env["NMH_ORCH_LIVE_ROOT"] = str(fixture)
        env["NMH_ORCH_MUTATE_MODE"] = "none"
        if extra:
            env.update(extra)
        # Never leak real signing/network credentials into orchestration.
        for key in ("NMH_DEVELOPER_ID_APPLICATION", "NMH_NOTARY_PROFILE", "NMH_RELEASE_UAT_EVIDENCE",
                    "NMH_UPDATE_FEED_URL", "NMH_SPARKLE_PRIVATE_KEY_FILE",
                    "NMH_SPARKLE_PUBLIC_ED_KEY", "NMH_SPARKLE_PUBLIC_ED_KEY_FILE"):
            if extra is None or key not in (extra or {}):
                env.pop(key, None)
        return env

    def test_orchestration_localonly_pinned_ignores_live_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            built = self.build_fixture(base)
            fixture, pinned = built["fixture"], built["pinned"]
            stub_bin, gate_log, tool_log, gh_marker = self.make_stub_bin(base)
            short = git(fixture, "rev-parse", "--short=12", "HEAD")
            build_id = f"{REAL_VERSION}+{short}"
            env = self.orch_env(stub_bin, gate_log, tool_log, gh_marker, fixture,
                                extra={"NMH_ORCH_MUTATE_MODE": "live-version-and-head"})
            result = subprocess.run(
                ["bash", str(fixture / "script" / "release-all.sh"), "--local-only"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, timeout=180,
            )
            self.assertEqual(result.returncode, 0, msg=f"stdout={result.stdout[-4000:]}\nstderr={result.stderr[-4000:]}")
            # Production branch ran: TEST_MODE was never set, so the stub bundle
            # shortcut was not taken; the fixture lifecycle build stub ran instead.
            self.assertNotIn("NMH_RELEASE_TEST_MODE", str(env))
            # Live was mutated after snapshot/gate start (VERSION/HEAD/source).
            self.assertEqual((fixture / "VERSION").read_text(encoding="utf-8").strip(), "0.0.0-evil")
            self.assertTrue((fixture / "untracked-evil.txt").is_file())
            self.assertNotEqual(git(fixture, "rev-parse", "HEAD"), pinned)
            self.assertIn("evil concurrent lifecycle mutation", (fixture / "script" / "lib" / "app_lifecycle.sh").read_text(encoding="utf-8"))
            # Gates ran from the pinned snapshot, not live.
            gate_text = gate_log.read_text(encoding="utf-8")
            self.assertIn("gate-ci snapshot_root=", gate_text)
            self.assertIn("pinned-source", gate_text)
            for line in gate_text.splitlines():
                if line.startswith("gate-ci snapshot_root="):
                    snap = line.split("=", 1)[1].strip()
                    self.assertIn("pinned-source", snap)
                    self.assertNotEqual(snap, str(fixture))
            # Real lifecycle checks ran against the pinned root/output: the
            # fixture build stub sources the actual pinned pipeline (same
            # release-all/env/snapshot bytes) and enforces dist beneath
            # <snapshot>/dist from the snapshot root.
            self.assertIn("fixture-build snapshot_root=", gate_text)
            for line in gate_text.splitlines():
                if line.startswith("fixture-build snapshot_root="):
                    self.assertIn("pinned-source", line)
                    self.assertIn("dist=", line)
                    self.assertIn("pinned-source/dist/release-build", line)
                    self.assertNotIn("0.0.0-evil", line)
            # Snapshot lifecycle source is pinned: live evil did not enter it.
            # The snapshot path is the gate-ci root (pinned-source).
            snap_roots = [l.split("=", 1)[1].strip() for l in gate_text.splitlines() if l.startswith("gate-ci snapshot_root=")]
            self.assertTrue(snap_roots)
            snap_lifecycle = pathlib.Path(snap_roots[0]) / "script" / "lib" / "app_lifecycle.sh"
            # Cleanup intentionally removes the snapshot before return. Compare
            # the digest captured while its build function was actually running.
            self.assertFalse(snap_lifecycle.exists())
            observed_lifecycle_sha = pathlib.Path(str(gate_log) + ".lifecycle-sha").read_text().split()[0]
            pinned_lifecycle = subprocess.check_output([
                "git", "-C", str(fixture), "show", f"{pinned}:script/lib/app_lifecycle.sh"
            ])
            self.assertEqual(observed_lifecycle_sha, hashlib.sha256(pinned_lifecycle).hexdigest())
            self.assertNotIn(b"evil concurrent lifecycle mutation", pinned_lifecycle)
            self.assertIn(b"output directory must stay beneath", pinned_lifecycle)
            # Build/metadata/validators used pinned bytes, not live evil.
            release_dir = fixture / "dist" / "release"
            manifests = list(release_dir.glob("NikoMusicHub-*-manifest.json"))
            self.assertEqual(len(manifests), 1)
            manifest = json.loads(manifests[0].read_text(encoding="utf-8"))
            self.assertEqual(manifest["version"], REAL_VERSION)
            self.assertEqual(manifest["commit"], pinned)
            self.assertEqual(manifest["build_id"], build_id)
            report = next(release_dir.glob("*-release-report.md"))
            report_text = report.read_text(encoding="utf-8")
            self.assertIn(pinned, report_text)
            self.assertNotIn("0.0.0-evil", report_text)
            prov = json.loads((release_dir / "snapshot-provenance.json").read_text(encoding="utf-8"))
            self.assertEqual(prov["pinned_commit"], pinned)
            # No live .build entered the artifact path; bundle came from the
            # pinned snapshot dist via the production branch (staged into
            # RELEASE_DIR/build), never the TEST_MODE shortcut.
            self.assertFalse((fixture / ".build" / "NikoMusicHub").exists())
            # Never touched real signing/network: local-only must not call them.
            tool_text = tool_log.read_text(encoding="utf-8")
            self.assertIn("hdiutil create", tool_text)
            self.assertIn("lipo -archs", tool_text)
            self.assertNotIn("codesign --force --timestamp --identifier", tool_text)
            self.assertNotIn("\n gh ", "\n " + tool_text)
            self.assertFalse(gh_marker.exists())
            # Six-asset publication unchanged: dry local-only publishes nothing.
            self.assertFalse(any(p.suffix == ".dmg" and "hosted" in p.name for p in release_dir.rglob("*")))

    def test_orchestration_public_freeze_uses_retained_bytes_after_original_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            built = self.build_fixture(base)
            fixture, pinned = built["fixture"], built["pinned"]
            short = git(fixture, "rev-parse", "--short=12", "HEAD")
            build_id = f"{REAL_VERSION}+{short}"
            original = base / "original-uat.json"
            write_valid_uat(original, pinned, build_id)
            frozen_sha_before = sha_file(original)
            stub_bin, gate_log, tool_log, gh_marker = self.make_stub_bin(base)
            env = self.orch_env(stub_bin, gate_log, tool_log, gh_marker, fixture, extra={
                "NMH_ORCH_MUTATE_MODE": "original-uat",
                "NMH_ORCH_ORIGINAL_UAT": str(original),
                "NMH_DEVELOPER_ID_APPLICATION": TEST_IDENTITY,
                "NMH_NOTARY_PROFILE": "orch-test-profile",
                "NMH_RELEASE_UAT_EVIDENCE": str(original),
            })
            result = subprocess.run(
                ["bash", str(fixture / "script" / "release-all.sh"), "--public", "--dry-run-publish"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, timeout=240,
            )
            self.assertEqual(result.returncode, 0, msg=f"stdout={result.stdout[-5000:]}\nstderr={result.stderr[-5000:]}")
            self.assertIn("not created yet; rehearsal", result.stdout + result.stderr)
            # Production branch ran without the TEST_MODE shortcut.
            self.assertNotIn("NMH_RELEASE_TEST_MODE", str(env))
            gate_text = gate_log.read_text(encoding="utf-8")
            self.assertIn("fixture-build snapshot_root=", gate_text)
            self.assertIn("pinned-source/dist/release-build", gate_text)
            # Original was mutated after freezing/validation (concurrent change).
            self.assertNotEqual(sha_file(original), frozen_sha_before)
            # Final approval uses the validated frozen retained bytes, not the mutated original.
            release_dir = fixture / "dist" / "release"
            finals = list(release_dir.glob("NikoMusicHub-*-uat.json"))
            self.assertEqual(len(finals), 1)
            final = finals[0]
            self.assertEqual(sha_file(final), frozen_sha_before)
            approvals = list(release_dir.glob("*-release-approval.json"))
            self.assertEqual(len(approvals), 1)
            approval = json.loads(approvals[0].read_text(encoding="utf-8"))
            self.assertEqual(approval["uat_evidence"]["sha256"], frozen_sha_before)
            self.assertEqual(approval["uat_evidence"]["file"], final.name)
            self.assertEqual(approval["commit"], pinned)
            # Stubs prove pinned execution; dry-run never publishes.
            self.assertFalse(gh_marker.exists())
            tool_text = tool_log.read_text(encoding="utf-8")
            self.assertIn("curl", tool_text)
            self.assertIn("codesign", tool_text)
            self.assertIn(TEST_IDENTITY, tool_text)

    def test_orchestration_public_rejects_mutated_frozen_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            built = self.build_fixture(base)
            fixture, pinned = built["fixture"], built["pinned"]
            short = git(fixture, "rev-parse", "--short=12", "HEAD")
            build_id = f"{REAL_VERSION}+{short}"
            original = base / "original-uat.json"
            write_valid_uat(original, pinned, build_id)
            stub_bin, gate_log, tool_log, gh_marker = self.make_stub_bin(base)
            env = self.orch_env(stub_bin, gate_log, tool_log, gh_marker, fixture, extra={
                "NMH_ORCH_MUTATE_MODE": "final-uat-bad",
                "NMH_DEVELOPER_ID_APPLICATION": TEST_IDENTITY,
                "NMH_NOTARY_PROFILE": "orch-test-profile",
                "NMH_RELEASE_UAT_EVIDENCE": str(original),
            })
            result = subprocess.run(
                ["bash", str(fixture / "script" / "release-all.sh"), "--public", "--dry-run-publish"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, timeout=240,
            )
            self.assertNotEqual(result.returncode, 0)
            combined = result.stdout + result.stderr
            self.assertTrue(
                ("frozen UAT evidence changed after validation" in combined)
                or ("must be passed" in combined)
                or ("UAT commit mismatch" in combined)
                or ("identity mismatch" in combined),
                msg=f"expected frozen/semantic rejection, got stdout={result.stdout[-4000:]}\nstderr={result.stderr[-4000:]}",
            )
            self.assertIn("mutated-final-uat=", gate_log.read_text(encoding="utf-8"))
            self.assertFalse(gh_marker.exists())

    def test_orchestration_public_key_override_rejects_before_publication(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            built = self.build_fixture(base)
            fixture, pinned = built["fixture"], built["pinned"]
            short = git(fixture, "rev-parse", "--short=12", "HEAD")
            build_id = f"{REAL_VERSION}+{short}"
            original = base / "original-uat.json"
            write_valid_uat(original, pinned, build_id)
            stub_bin, gate_log, tool_log, gh_marker = self.make_stub_bin(base)
            for key, needle in (
                ({"NMH_SPARKLE_PUBLIC_ED_KEY": ALT_KEY}, "NMH_SPARKLE_PUBLIC_ED_KEY"),
                ({"NMH_SPARKLE_PUBLIC_ED_KEY_FILE": "/tmp/alt-key"}, "NMH_SPARKLE_PUBLIC_ED_KEY_FILE"),
                ({"NMH_RELEASE_TEST_MODE": "1"}, "NMH_RELEASE_TEST_MODE"),
            ):
                extra = {
                    "NMH_DEVELOPER_ID_APPLICATION": TEST_IDENTITY,
                    "NMH_NOTARY_PROFILE": "orch-test-profile",
                    "NMH_RELEASE_UAT_EVIDENCE": str(original),
                }
                extra.update(key)
                env = self.orch_env(stub_bin, gate_log, tool_log, gh_marker, fixture, extra=extra)
                result = subprocess.run(
                    ["bash", str(fixture / "script" / "release-all.sh"), "--public", "--dry-run-publish"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, timeout=120,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(needle, result.stderr)
                self.assertFalse(gh_marker.exists())
                release_dir = fixture / "dist" / "release"
                # Rejected before artifact publication: no DMG was published.
                if release_dir.exists():
                    self.assertEqual(list(release_dir.glob("*.dmg")), [])

    def test_orchestration_missing_credentials_fails_closed_with_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = pathlib.Path(raw)
            built = self.build_fixture(base)
            fixture = built["fixture"]
            stub_bin, gate_log, tool_log, gh_marker = self.make_stub_bin(base)
            env = self.orch_env(stub_bin, gate_log, tool_log, gh_marker, fixture, extra={})
            result = subprocess.run(
                ["bash", str(fixture / "script" / "release-all.sh"), "--public", "--dry-run-publish"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, timeout=120,
            )
            # Capture stdout/stderr for coordinator diagnosis of actual bash/PATH/env;
            # do not guess the fatal-expansion status (minimal /bin/bash repro is 127).
            self.assertNotEqual(
                result.returncode,
                0,
                msg=f"stdout={result.stdout[-4000:]}\nstderr={result.stderr[-4000:]}",
            )
            self.assertIn(
                "NMH_DEVELOPER_ID_APPLICATION",
                result.stderr,
                msg=f"stdout={result.stdout[-4000:]}\nstderr={result.stderr[-4000:]}",
            )
            self.assertFalse(gh_marker.exists())
            # Bounded cleanup even on failure: no provenance run dir is left behind.
            parent = fixture / "dist"
            leftovers = list(parent.glob("release.provenance-*")) + list(parent.glob("*.provenance-*"))
            self.assertEqual(leftovers, [])


if __name__ == "__main__":
    unittest.main()
