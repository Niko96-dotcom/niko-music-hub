#!/usr/bin/env bash
# Shared release constants. Source this file from release scripts.
# shellcheck shell=bash

NMH_RELEASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NMH_RELEASE_ROOT="$(cd "$NMH_RELEASE_SCRIPT_DIR/.." && pwd)"

nmh_release_version() {
  local version_file="${NMH_VERSION_FILE:-$NMH_RELEASE_ROOT/VERSION}"
  if [[ ! -f "$version_file" ]]; then
    echo "missing canonical VERSION file: $version_file" >&2
    return 1
  fi
  local version
  version="$(tr -d '[:space:]' <"$version_file")"
  if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){2}(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "invalid release version '$version' in $version_file; expected semver like 1.4.0" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

nmh_git_commit() {
  git -C "$NMH_RELEASE_ROOT" rev-parse HEAD
}

nmh_git_short_commit() {
  git -C "$NMH_RELEASE_ROOT" rev-parse --short=12 HEAD
}

nmh_git_build_number() {
  git -C "$NMH_RELEASE_ROOT" rev-list --count HEAD
}

nmh_release_tag() {
  printf 'v%s\n' "$(nmh_release_version)"
}

nmh_release_build_id() {
  printf '%s+%s\n' "$(nmh_release_version)" "$(nmh_git_short_commit)"
}
