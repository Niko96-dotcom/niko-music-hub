#!/usr/bin/env bash
# Pinned-source and frozen-UAT provenance helpers for Niko Music Hub releases.
# shellcheck shell=bash
#
# R1: every release executes the pinned exact git commit from an isolated
# source snapshot with isolated .build/output. Concurrent changes in the
# invoking checkout cannot enter the artifact or change provenance, because
# the snapshot is a detached worktree (`git worktree add --detach
# <pinned-commit>`) with genuine .git metadata, never live working-tree files
# and never `git archive` (which has no .git, so helper git calls would
# discover the enclosing live repo). The build reads the snapshot.
#
# R2: UAT evidence is frozen once to a private run location BEFORE any UAT
# validation. Hashing, final validation and approval all use the same frozen
# bytes even if the external original changes afterwards.
#
# R4: production Sparkle public-key continuity. The shipped app/feed must use
# the repository SPARKLE_PUBLIC_ED_KEY from the pinned commit, never a silent
# NMH_SPARKLE_PUBLIC_ED_KEY or NMH_SPARKLE_PUBLIC_ED_KEY_FILE alternate.
# Test/local overrides remain explicit (local-only keeps them); public mode
# rejects them and rejects any resolved-vs-pinned mismatch before build.
#
# Layout (all under a private run dir that is a sibling of RELEASE_DIR, never
# beneath it, so later `rm -rf "$RELEASE_DIR"` cannot remove it):
#   <release-dir>.provenance-<short12>-<pid>/
#     pinned-source/            # detached worktree at <pinned-commit> with genuine .git
#     snapshot-provenance.json  # pinned commit + git metadata + file hashes
#     frozen-uat.json           # frozen UAT bytes (public mode only)
#
# Cleanup is safe and bounded (nmh_snapshot_cleanup): only a run dir beneath
# its allowed parent and carrying the provenance marker is removed. The
# invoking working tree and untracked content are never touched. Reviewable
# outputs/logs stay in RELEASE_DIR; the run dir is removed on EXIT.
#
# These helpers take explicit paths so the behavioral harness can exercise
# them against disposable temp git fixtures with stubbed side effects. They
# never contact signing, notary, or publication, never emit secrets, and never
# create public bypass envs.

# Reject public-mode source/config overrides that would make VERSION,
# BUNDLE_ID, Package.swift, architectures, or Sparkle key drift from the
# pinned commit. Local-only and dev/test use keep explicit overrides.
nmh_snapshot_reject_public_overrides() {
  local mode="${1:-}"
  if [[ "$mode" != "public" ]]; then
    return 0
  fi
  if [[ -n "${NMH_VERSION_FILE:-}" ]]; then
    echo "public release refuses NMH_VERSION_FILE; public VERSION must come from the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_BUNDLE_ID_FILE:-}" ]]; then
    echo "public release refuses NMH_BUNDLE_ID_FILE; public BUNDLE_ID must come from the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_PACKAGE_FILE:-}" ]]; then
    echo "public release refuses NMH_PACKAGE_FILE; public Package.swift minimum macOS must come from the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_RELEASE_ARCHITECTURES_FILE:-}" ]]; then
    echo "public release refuses NMH_RELEASE_ARCHITECTURES_FILE; public architectures must come from the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    echo "public release refuses NMH_SPARKLE_PUBLIC_ED_KEY; public app/feed must use the repository SPARKLE_PUBLIC_ED_KEY from the pinned commit, never an environment alternate (use local-only for test keys)" >&2
    return 1
  fi
  if [[ -n "${NMH_SPARKLE_PUBLIC_ED_KEY_FILE:-}" ]]; then
    echo "public release refuses NMH_SPARKLE_PUBLIC_ED_KEY_FILE; public app/feed must use the repository SPARKLE_PUBLIC_ED_KEY from the pinned commit, never a file alternate (use local-only for test keys)" >&2
    return 1
  fi
  if [[ -n "${NMH_BUNDLE_ID:-}" ]]; then
    echo "public release refuses NMH_BUNDLE_ID; public bundle identity must come from the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_APP_NAME:-}" ]]; then
    echo "public release refuses NMH_APP_NAME; public product name must come from the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_MARKETING_VERSION:-}" ]]; then
    echo "public release refuses NMH_MARKETING_VERSION; public VERSION must come from the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_BUILD_VERSION:-}" ]]; then
    echo "public release refuses NMH_BUILD_VERSION; public build number must come from the pinned commit count, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_SOURCE_COMMIT:-}" ]]; then
    echo "public release refuses NMH_SOURCE_COMMIT; public source commit must be the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_BUILD_ID:-}" ]]; then
    echo "public release refuses NMH_BUILD_ID; public build ID must be VERSION+short12 of the pinned commit, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_BUILD_CONFIGURATION:-}" ]]; then
    echo "public release refuses NMH_BUILD_CONFIGURATION; public builds are always release configuration from the pinned commit (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_MIN_SYSTEM_VERSION:-}" ]]; then
    echo "public release refuses NMH_MIN_SYSTEM_VERSION; public minimum macOS must come from the pinned Package.swift, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ -n "${NMH_DIST_DIR:-}" ]]; then
    echo "public release refuses NMH_DIST_DIR; public build output must stay in the isolated release directory, not the environment (use local-only for test overrides)" >&2
    return 1
  fi
  if [[ "${NMH_RELEASE_TEST_MODE:-}" == "1" ]]; then
    echo "public release refuses NMH_RELEASE_TEST_MODE; public builds must run the pinned Swift build, never the test stub bundle (use local-only for test builds)" >&2
    return 1
  fi
}

# Print (and create) the private run dir sibling to the release dir.
# Usage: nmh_snapshot_init_run_dir <release-dir> <short-commit>
nmh_snapshot_init_run_dir() {
  local release_dir="${1:?missing release dir}"
  local short_commit="${2:?missing short commit}"
  local run_dir="${release_dir}.provenance-${short_commit}-$$"
  mkdir -p "$run_dir" || {
    echo "cannot create provenance run dir: $run_dir" >&2
    return 1
  }
  printf '%s\n' "$run_dir"
}

# Materialize the pinned commit into <run-dir>/pinned-source via a detached
# worktree (object database with genuine .git metadata, never live files) and
# write <run-dir>/snapshot-provenance.json with actual git metadata plus
# canonical file hashes. Verifies the snapshot HEAD equals the pinned commit
# and snapshot files equal `git show <commit>:<file>` for every canonical path.
# Prints the snapshot source path.
nmh_snapshot_create_pinned_source() {
  local repo_root="${1:?missing repo root}"
  local commit="${2:?missing pinned commit}"
  local run_dir="${3:?missing run dir}"
  local dest="$run_dir/pinned-source"
  local record="$run_dir/snapshot-provenance.json"

  local pinned_full=""
  if ! pinned_full="$(git -C "$repo_root" rev-parse "$commit^{commit}" 2>/dev/null)"; then
    echo "pinned commit not found in $repo_root: $commit" >&2
    return 1
  fi
  if ! git -C "$repo_root" cat-file -e "$pinned_full" 2>/dev/null; then
    echo "pinned commit not found in $repo_root: $commit" >&2
    return 1
  fi
  if [[ -e "$dest" ]]; then
    echo "snapshot destination already exists (refusing to overwrite): $dest" >&2
    return 1
  fi
  mkdir -p "$run_dir" || {
    echo "cannot create run dir: $run_dir" >&2
    return 1
  }
  if ! git -C "$repo_root" worktree add --detach "$dest" "$pinned_full" >/dev/null 2>&1; then
    echo "failed to materialize pinned commit $pinned_full into $dest via detached worktree" >&2
    return 1
  fi
  if [[ ! -e "$dest/.git" ]]; then
    echo "pinned snapshot has no .git metadata (not a worktree): $dest" >&2
    return 1
  fi
  local actual_head=""
  if ! actual_head="$(git -C "$dest" rev-parse HEAD 2>/dev/null)"; then
    echo "cannot read snapshot HEAD in $dest" >&2
    return 1
  fi
  if [[ "$actual_head" != "$pinned_full" ]]; then
    echo "snapshot HEAD $actual_head differs from pinned commit $pinned_full" >&2
    return 1
  fi

  # Record actual git metadata from the snapshot itself (genuine .git, so a
  # branch change in the invoking checkout cannot make validation read another
  # commit) plus snapshot file hashes (reviewable provenance).
  if ! /usr/bin/python3 - "$dest" "$pinned_full" "$dest" "$record" <<'PY'; then
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

repo_root, commit, dest, record = sys.argv[1:5]

def git_output(*args):
    return subprocess.run(
        ["git", "-C", dest] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

short = git_output("rev-parse", "--short=12", "HEAD")
build = git_output("rev-list", "--count", "HEAD")
log = git_output("log", "-1", "--format=%H%n%T%n%an%n%ae%n%aI%n%s", "HEAD")
if short.returncode != 0 or build.returncode != 0 or log.returncode != 0:
    raise SystemExit(f"cannot read git metadata for {commit}")
head = git_output("rev-parse", "HEAD")
if head.returncode != 0 or head.stdout.strip() != commit:
    raise SystemExit(f"snapshot HEAD {head.stdout.strip()!r} != pinned {commit!r}")

canonical = ["VERSION", "BUNDLE_ID", "RELEASE_ARCHITECTURES", "Package.swift", "SPARKLE_PUBLIC_ED_KEY"]
files = {}
for rel in canonical:
    path = pathlib.Path(dest) / rel
    if path.is_file():
        files[rel] = {
            "exists": True,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "size": path.stat().st_size,
        }
    else:
        files[rel] = {"exists": False}

payload = {
    "pinned_commit": commit,
    "short_commit": short.stdout.strip(),
    "build_number": build.stdout.strip(),
    "git_log": log.stdout.strip(),
    "created_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "canonical_files": files,
}
pathlib.Path(record).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
    echo "failed to write snapshot provenance record: $record" >&2
    return 1
  fi

  # The snapshot must equal the pinned commit's tracked bytes: concurrent live
  # changes cannot have entered because the worktree checks out the object
  # database at the pinned commit, never live working-tree files.
  local rel
  for rel in VERSION BUNDLE_ID RELEASE_ARCHITECTURES Package.swift SPARKLE_PUBLIC_ED_KEY; do
    if git -C "$repo_root" cat-file -e "$pinned_full:$rel" 2>/dev/null; then
      if [[ ! -f "$dest/$rel" ]]; then
        echo "snapshot missing pinned file $rel (commit $pinned_full has it)" >&2
        return 1
      fi
      if ! git -C "$repo_root" show "$pinned_full:$rel" | cmp -s - "$dest/$rel"; then
        echo "snapshot file $rel differs from pinned commit $pinned_full" >&2
        return 1
      fi
    else
      if [[ -e "$dest/$rel" ]]; then
        echo "snapshot has unexpected $rel not present at pinned commit $pinned_full" >&2
        return 1
      fi
    fi
  done

  printf '%s\n' "$dest"
}

# Freeze one file (UAT evidence) into the private run dir BEFORE any validation.
# Copies bytes once; later stages hash/validate/use the frozen copy even if the
# external original changes. Prints the frozen path.
nmh_snapshot_freeze_uat() {
  local src="${1:?missing source UAT file}"
  local run_dir="${2:?missing run dir}"
  local dest="$run_dir/frozen-uat.json"
  if [[ ! -f "$src" ]]; then
    echo "cannot freeze missing UAT evidence: $src" >&2
    return 1
  fi
  mkdir -p "$run_dir" || {
    echo "cannot create run dir: $run_dir" >&2
    return 1
  }
  if [[ -e "$dest" ]]; then
    echo "frozen UAT already exists (freeze once): $dest" >&2
    return 1
  fi
  cp "$src" "$dest" || {
    echo "failed to freeze UAT evidence into $dest" >&2
    return 1
  }
  if ! cmp -s "$src" "$dest"; then
    echo "frozen UAT copy mismatch: $dest" >&2
    return 1
  fi
  printf '%s\n' "$dest"
}

# Generic freeze helper for tests: freeze <src> as <run-dir>/<basename>.
nmh_snapshot_freeze_file() {
  local src="${1:?missing source file}"
  local run_dir="${2:?missing run dir}"
  local base="${3:?missing frozen basename}"
  local dest="$run_dir/$base"
  if [[ ! -f "$src" ]]; then
    echo "cannot freeze missing file: $src" >&2
    return 1
  fi
  case "$base" in
    ""|*/*)
      echo "frozen basename must be a plain filename: $base" >&2
      return 1
      ;;
  esac
  mkdir -p "$run_dir" || {
    echo "cannot create run dir: $run_dir" >&2
    return 1
  }
  if [[ -e "$dest" ]]; then
    echo "frozen destination already exists (freeze once): $dest" >&2
    return 1
  fi
  cp "$src" "$dest" || {
    echo "failed to freeze $src into $dest" >&2
    return 1
  }
  if ! cmp -s "$src" "$dest"; then
    echo "frozen copy mismatch: $dest" >&2
    return 1
  fi
  printf '%s\n' "$dest"
}

# Read the canonical Sparkle public key from a snapshot root, ignoring all
# NMH_SPARKLE_* environment alternates. Prints nothing when absent.
nmh_snapshot_canonical_key() {
  local snapshot_root="${1:?missing snapshot root}"
  local key_file="$snapshot_root/SPARKLE_PUBLIC_ED_KEY"
  if [[ ! -f "$key_file" ]]; then
    return 0
  fi
  local key
  key="$(tr -d '[:space:]' <"$key_file")"
  if [[ -z "$key" ]]; then
    return 0
  fi
  if ! /usr/bin/python3 - "$key" <<'PY_KEY'; then
import base64
import sys

try:
    decoded = base64.b64decode(sys.argv[1], validate=True)
except Exception:
    raise SystemExit("SUPublicEDKey is not valid base64")
if len(decoded) != 32:
    raise SystemExit(f"SUPublicEDKey must decode to 32 bytes, got {len(decoded)}")
PY_KEY
    return 1
  fi
  printf '%s\n' "$key"
}

# R4 continuity: the resolved public key must equal the pinned snapshot key.
# Never silently accept an environment/file alternate in production.
nmh_snapshot_verify_sparkle_continuity() {
  local snapshot_root="${1:?missing snapshot root}"
  local resolved_key="${2:-}"
  local snapshot_key
  if ! snapshot_key="$(nmh_snapshot_canonical_key "$snapshot_root")"; then
    return 1
  fi
  if [[ "$resolved_key" != "$snapshot_key" ]]; then
    echo "public release Sparkle public key mismatch: resolved key differs from pinned commit's SPARKLE_PUBLIC_ED_KEY; refusing to build/publish (public releases must not set NMH_SPARKLE_PUBLIC_ED_KEY or _FILE)" >&2
    return 1
  fi
}

# Copy validated frozen UAT bytes into the final release output without
# mutation, so the evidence stays reviewable after the private run dir is
# cleaned on EXIT. Prints the final path. Approval basename/hash must agree
# with this file, and final semantic validation must use it (same bytes).
# Usage: nmh_snapshot_publish_frozen_uat <frozen-uat> <release-dir> <version>
nmh_snapshot_publish_frozen_uat() {
  local frozen="${1:?missing frozen UAT}"
  local release_dir="${2:?missing release dir}"
  local version="${3:?missing version}"
  local dest="$release_dir/NikoMusicHub-$version-uat.json"
  if [[ ! -f "$frozen" ]]; then
    echo "cannot publish missing frozen UAT: $frozen" >&2
    return 1
  fi
  if [[ -e "$dest" ]]; then
    echo "final UAT already exists (refusing to overwrite): $dest" >&2
    return 1
  fi
  cp "$frozen" "$dest" || {
    echo "failed to copy frozen UAT into $dest" >&2
    return 1
  }
  if ! cmp -s "$frozen" "$dest"; then
    echo "final UAT copy mutated bytes: $dest" >&2
    return 1
  fi
  printf '%s\n' "$dest"
}

# Safe, bounded cleanup: only removes a run dir beneath its allowed parent that
# carries the provenance marker. Never touches the working tree or untracked
# content outside the run dir. Reviewable RELEASE_DIR outputs are untouched.
# Detached worktrees are deregistered first (bounded to this dest only).
nmh_snapshot_cleanup() {
  local run_dir="${1:?missing run dir}"
  local allowed_parent="${2:?missing allowed parent}"
  if ! /usr/bin/python3 - "$run_dir" "$allowed_parent" <<'PY'; then
import os
import sys

run = os.path.realpath(sys.argv[1])
parent = os.path.realpath(sys.argv[2])
if run == parent:
    raise SystemExit(f"refusing to clean the parent itself: {run}")
if os.path.commonpath([parent, run]) != parent:
    raise SystemExit(f"snapshot run dir outside allowed parent: {run} not under {parent}")
base = os.path.basename(run)
if ".provenance-" not in base:
    raise SystemExit(f"refusing to clean non-provenance dir: {run}")
marker = os.path.join(run, "snapshot-provenance.json")
if not os.path.isfile(marker):
    raise SystemExit(f"refusing to clean run dir without provenance marker: {run}")
PY
    return 1
  fi
  local dest="$run_dir/pinned-source"
  if [[ -f "$dest/.git" ]]; then
    local common_dir=""
    common_dir="$(git -C "$dest" rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "$common_dir" && -d "$common_dir" ]]; then
      (cd "${TMPDIR:-/tmp}" && git --git-dir="$common_dir" worktree remove --force "$dest" 2>/dev/null || true)
      (cd "${TMPDIR:-/tmp}" && git --git-dir="$common_dir" worktree prune 2>/dev/null || true)
    else
      (cd "${TMPDIR:-/tmp}" && git -C "$dest" worktree remove --force "$dest" 2>/dev/null || true)
    fi
  fi
  rm -rf "$run_dir"
}
