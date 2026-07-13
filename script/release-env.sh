#!/usr/bin/env bash
# Shared release constants. Source this file from release scripts.
# shellcheck shell=bash

NMH_RELEASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NMH_RELEASE_ROOT="$(cd "$NMH_RELEASE_SCRIPT_DIR/.." && pwd)"

nmh_json_value() {
  local json_file="$1"
  local dotted_key="$2"
  /usr/bin/python3 - "$json_file" "$dotted_key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for component in sys.argv[2].split("."):
    value = value[component]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, sort_keys=True))
else:
    print(value)
PY
}

nmh_json_lint() {
  /usr/bin/python3 -m json.tool "$1" >/dev/null
}

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

nmh_bundle_id() {
  local bundle_id_file="${NMH_BUNDLE_ID_FILE:-$NMH_RELEASE_ROOT/BUNDLE_ID}"
  if [[ ! -f "$bundle_id_file" ]]; then
    echo "missing canonical BUNDLE_ID file: $bundle_id_file" >&2
    return 1
  fi
  local bundle_id
  bundle_id="$(tr -d '[:space:]' <"$bundle_id_file")"
  if [[ ! "$bundle_id" =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*){2,}$ ]]; then
    echo "invalid bundle identifier '$bundle_id' in $bundle_id_file; expected reverse-DNS form" >&2
    return 1
  fi
  case "$bundle_id" in
    local.*|test.*|example.*|*.example.*)
      echo "non-production bundle identifier '$bundle_id' in $bundle_id_file" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$bundle_id"
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
