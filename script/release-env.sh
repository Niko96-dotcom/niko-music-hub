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
    value = value[int(component)] if isinstance(value, list) else value[component]
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

nmh_release_min_macos_version() {
  local package_file="${NMH_PACKAGE_FILE:-$NMH_RELEASE_ROOT/Package.swift}"
  if [[ ! -f "$package_file" ]]; then
    echo "missing Package.swift for minimum macOS contract: $package_file" >&2
    return 1
  fi
  local minimum_version
  minimum_version="$(sed -nE 's/.*\.macOS\("([0-9]+(\.[0-9]+)*)"\).*/\1/p' "$package_file" | head -n 1)"
  if [[ ! "$minimum_version" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "invalid minimum macOS version in $package_file: '$minimum_version'" >&2
    return 1
  fi
  printf '%s\n' "$minimum_version"
}

nmh_release_architectures() {
  local architecture_file="${NMH_RELEASE_ARCHITECTURES_FILE:-$NMH_RELEASE_ROOT/RELEASE_ARCHITECTURES}"
  if [[ ! -f "$architecture_file" ]]; then
    echo "missing canonical release architecture file: $architecture_file" >&2
    return 1
  fi

  local entries
  if ! entries="$(awk '
    /^[[:space:]]*(#|$)/ { next }
    NF != 1 { exit 2 }
    { print $1 }
  ' "$architecture_file")"; then
    echo "invalid release architecture file (one architecture per non-comment line): $architecture_file" >&2
    return 1
  fi
  if [[ -z "$entries" ]]; then
    echo "release architecture contract is empty: $architecture_file" >&2
    return 1
  fi

  local architecture
  for architecture in $entries; do
    case "$architecture" in
      arm64|x86_64) ;;
      *)
        echo "unsupported release architecture '$architecture' in $architecture_file" >&2
        return 1
        ;;
    esac
  done

  local entry_count unique_count normalized
  entry_count="$(printf '%s\n' $entries | wc -l | tr -d '[:space:]')"
  unique_count="$(printf '%s\n' $entries | sort -u | wc -l | tr -d '[:space:]')"
  if [[ "$entry_count" != "$unique_count" ]]; then
    echo "duplicate release architecture in $architecture_file" >&2
    return 1
  fi
  normalized="$(printf '%s\n' $entries | sort -u | paste -sd' ' -)"
  printf '%s\n' "$normalized"
}

nmh_validate_release_host_architecture() {
  local host_architecture
  host_architecture="$(uname -m)"
  local supported_architectures
  supported_architectures="$(nmh_release_architectures)"
  if ! printf '%s\n' "$supported_architectures" | tr ' ' '\n' | grep -Fxq "$host_architecture"; then
    echo "release architecture contract does not include host architecture '$host_architecture' (supported: $supported_architectures)" >&2
    return 1
  fi
}

# Canonical update-feed contract.
#
# This URL is compiled into every shipped bundle and old installs poll it
# forever, so it is a one-way door: changing it strands every build already in
# the field. NMH_UPDATE_FEED_URL exists only to point a deliberately labeled
# test build at a test feed; it must never be used for a public release.
nmh_release_repository_url() {
  printf 'https://github.com/Niko96-dotcom/niko-music-hub\n'
}

# Where a published release's assets are downloaded from. Sparkle enclosure URLs
# are built from this, so it must agree with the channel docs/release.md declares.
nmh_release_download_url_prefix() {
  local tag="${1:?missing release tag}"
  printf '%s/releases/download/%s/\n' "$(nmh_release_repository_url)" "$tag"
}

nmh_update_feed_url() {
  local url="${NMH_UPDATE_FEED_URL:-$(nmh_release_repository_url)/releases/latest/download/appcast.xml}"
  if [[ "$url" != https://* ]]; then
    echo "update feed URL must be HTTPS: $url" >&2
    return 1
  fi
  printf '%s\n' "$url"
}

# Highest sparkle:version currently published on the live feed: the number a
# candidate's CFBundleVersion must beat before Sparkle offers it to anyone.
# Fails on any transport or parse error; the feed has existed since 1.5.0 and
# a release that cannot see it must not guess.
nmh_live_feed_max_build_number() {
  local url
  url="$(nmh_update_feed_url)" || return 1
  curl -4 -fsSL --max-time 30 "$url" | /usr/bin/python3 -c '
import sys
import xml.etree.ElementTree as ElementTree

namespaces = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ElementTree.fromstring(sys.stdin.read())
versions = [int(node.text.strip()) for node in root.iterfind(".//sparkle:version", namespaces)]
if not versions:
    raise SystemExit("live update feed has no sparkle:version entries")
print(max(versions))
'
}

# Public half of the EdDSA key pair that signs update enclosures.
#
# The private half lives only in the release owner's Keychain. Prints nothing
# and succeeds when the file is absent: a build without a key ships without
# update keys at all rather than with an unverifiable update path.
nmh_sparkle_public_ed_key() {
  local key_file="${NMH_SPARKLE_PUBLIC_ED_KEY_FILE:-$NMH_RELEASE_ROOT/SPARKLE_PUBLIC_ED_KEY}"
  local key="${NMH_SPARKLE_PUBLIC_ED_KEY:-}"
  if [[ -z "$key" ]]; then
    [[ -f "$key_file" ]] || return 0
    key="$(tr -d '[:space:]' <"$key_file")"
  fi
  [[ -n "$key" ]] || return 0

  # An ed25519 public key is 32 raw bytes; anything else would be embedded as a
  # key that can never validate a real signature.
  if ! /usr/bin/python3 - "$key" <<'PY_KEY'
import base64
import sys

try:
    decoded = base64.b64decode(sys.argv[1], validate=True)
except Exception:
    raise SystemExit("SUPublicEDKey is not valid base64")
if len(decoded) != 32:
    raise SystemExit(f"SUPublicEDKey must decode to 32 bytes, got {len(decoded)}")
PY_KEY
  then
    return 1
  fi
  printf '%s\n' "$key"
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

# The strict E2E gate reads the app's window through accessibility, which macOS
# withholds while the console is locked; the public pipeline burned eight minutes
# of gates before finding that out. Check up front instead.
nmh_console_locked() {
  local registry
  registry="$(/usr/sbin/ioreg -n Root -d1 -a 2>/dev/null || true)"
  [[ "$(grep -A1 IOConsoleLocked <<<"$registry" || true)" == *"<true/>"* ]]
}

# notarytool uploads to this S3 bucket over IPv4 and gives up after ~100 s. The
# API host answering is not enough: with the bucket unreachable every run dies
# after the gates with HTTPClientError.deadlineExceeded.
NMH_NOTARY_UPLOAD_HOST="https://notary-submissions-prod.s3.amazonaws.com/"

nmh_notary_upload_endpoint_reachable() {
  local code
  code="$(curl -4 --silent --output /dev/null --max-time 15 --write-out '%{http_code}' "$NMH_NOTARY_UPLOAD_HOST" 2>/dev/null || true)"
  [[ "$code" == "403" || "$code" == "200" ]]
}
