#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nmh-release-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

assert_fail() {
  local name="$1"
  shift
  if "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
    echo "expected failure but command passed: $name" >&2
    exit 1
  fi
}

assert_pass() {
  local name="$1"
  shift
  "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "expected '$needle' in $file" >&2
    sed -n '1,120p' "$file" >&2
    exit 1
  fi
}

line_number() {
  local needle="$1"
  local file="$2"
  awk -v needle="$needle" 'index($0, needle) { print NR; exit }' "$file"
}

assert_order() {
  local first="$1"
  local second="$2"
  local file="$3"
  local first_line second_line
  first_line="$(line_number "$first" "$file")"
  second_line="$(line_number "$second" "$file")"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "expected '$first' before '$second' in $file" >&2
    exit 1
  fi
}

echo "== release version verifier =="
assert_pass version-ok "$ROOT/script/release-version-verify.sh"
assert_fail stale-version "$ROOT/script/release-version-verify.sh" --previous-version 1.4
assert_contains "$TMP/stale-version.err" "previous version 1.4 appears outside allowlist"

echo "== public-tree hygiene =="
assert_pass hygiene "$ROOT/script/public-tree-hygiene.sh"

echo "== checksum basename validation =="
CHECK_DIR="$TMP/checksum"
mkdir -p "$CHECK_DIR"
printf 'payload' >"$CHECK_DIR/NikoMusicHub-test.dmg"
(cd "$CHECK_DIR" && shasum -a 256 NikoMusicHub-test.dmg >NikoMusicHub-test.dmg.sha256)
if grep -q '/' "$CHECK_DIR/NikoMusicHub-test.dmg.sha256"; then
  echo "checksum file unexpectedly contains a path" >&2
  exit 1
fi

echo "== release command order stays fail-closed =="
assert_order 'log "build app bundle"' 'log "package dmg"' "$ROOT/script/release-all.sh"
assert_order 'log "package dmg"' 'log "checksums and manifest"' "$ROOT/script/release-all.sh"
assert_order 'log "checksums and manifest"' 'log "publication"' "$ROOT/script/release-all.sh"
assert_order 'log "public app signature validation"' 'log "checksums and manifest"' "$ROOT/script/release-all.sh"
assert_order 'run notary-dmg' 'log "checksums and manifest"' "$ROOT/script/release-all.sh"
assert_order 'run hdiutil-create' '(cd "$RELEASE_DIR" && shasum' "$ROOT/script/release-all.sh"

echo "== hardened runtime output variants are accepted =="
for script in "$ROOT/script/release-all.sh" "$ROOT/script/validate-release-artifact.sh"; do
  grep -Fq 'Runtime\ Version' "$script" || {
    echo "missing Runtime Version verifier in $script" >&2
    exit 1
  }
  grep -Fq 'flags=.*runtime' "$script" || {
    echo "missing runtime flags verifier in $script" >&2
    exit 1
  }
done

echo "== public mode fails closed without credentials =="
assert_fail public-missing-creds "$ROOT/script/release-all.sh" --public --dry-run-publish --skip-tests
assert_contains "$TMP/public-missing-creds.err" "NMH_DEVELOPER_ID_APPLICATION"

echo "== explicit local-only mode does not publish =="
assert_fail local-publish "$ROOT/script/release-all.sh" --local-only --publish --skip-tests
assert_contains "$TMP/local-publish.err" "local-only release cannot publish"

echo "release script regression tests passed."
