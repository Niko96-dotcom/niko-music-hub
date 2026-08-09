#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCLUDE_UNTRACKED=false
PUBLIC_RELEASE=false

usage() {
  cat >&2 <<'USAGE'
usage: script/public-tree-hygiene.sh [--include-untracked] [--public-release]

Checks the public/tracked tree for release-hostile files and credential-shaped
content. --include-untracked performs a stricter local sweep. --public-release
also rejects private planning/agent state and real home-directory paths; use it
for a source tree that is about to become publicly visible.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-untracked) INCLUDE_UNTRACKED=true; shift ;;
    --public-release) PUBLIC_RELEASE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

# Kept for compatibility with existing callers. New public-release callers use
# the explicit flag so the strict policy is visible in their command record.
if [[ -n "${NMH_PUBLIC_TREE_STRICT_PLANNING:-}" ]]; then
  PUBLIC_RELEASE=true
fi

cd "$ROOT"

FILES=()
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r file; do
    FILES+=("${file#./}")
  done < <(find . -type f \
    -not -path './.build/*' \
    -not -path './dist/*' \
    -not -path './.git/*' \
    -print | LC_ALL=C sort)
elif [[ "$INCLUDE_UNTRACKED" == true ]]; then
  while IFS= read -r file; do
    FILES+=("$file")
  done < <(git ls-files --cached --others --exclude-standard)
else
  while IFS= read -r file; do
    FILES+=("$file")
  done < <(git ls-files)
fi

FAILURES=()

for file in "${FILES[@]}"; do
  case "$file" in
    *.DS_Store|*/.DS_Store|.DS_Store) FAILURES+=("$file: Finder metadata must not ship") ;;
    .env|*.env|.env.*|*/.env|*/.env.*) FAILURES+=("$file: environment/secret file must not ship") ;;
    *.p12|*.pfx|*.pem|*.key|*.mobileprovision) FAILURES+=("$file: private signing material must not ship") ;;
    DerivedData/*|dist/*|.build/*|tmp/*|*.xcresult) FAILURES+=("$file: build output must not ship") ;;
    .ai/runs/*) FAILURES+=("$file: local AI run logs must not ship") ;;
  esac
  if [[ "$PUBLIC_RELEASE" == true ]]; then
    case "$file" in
      .planning/*|.codex/*|.cursor/*|.ai/*)
        FAILURES+=("$file: public source tree must not ship private planning or agent state")
        ;;
    esac
  fi
done

SECRET_PATTERN='(AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}|gh[pousr]_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{32,})'
for file in "${FILES[@]}"; do
  case "$file" in
    script/public-tree-hygiene.sh|script/verify-source-distribution.py|Tests/test_source_distribution_scripts.sh|docs/release.md|docs/release-validation.md) continue ;;
  esac
  if [[ -f "$file" ]]; then
    while IFS= read -r hit; do
      [[ -n "$hit" ]] && FAILURES+=("$hit: credential-shaped string")
    done < <(rg -n -I "$SECRET_PATTERN" "$file" || true)
  fi
done

if [[ "$PUBLIC_RELEASE" == true ]]; then
  # Source/test fixtures often use generic synthetic paths. Public-facing docs,
  # evidence, and state files must never retain a real local home path.
  HOME_PATH_PATTERN='/(Users|home)/[[:alnum:]_.-]+(/|$)'
  for file in "${FILES[@]}"; do
    case "$file" in
      Sources/*|Tests/*|Fixtures/*|script/*) continue ;;
    esac
    if [[ -f "$file" ]]; then
      while IFS= read -r hit; do
        [[ -n "$hit" ]] && FAILURES+=("$hit: real home-directory path must not ship in a public source tree")
      done < <(rg -n -I "$HOME_PATH_PATTERN" "$file" || true)
    fi
  done
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "public tree hygiene failed:" >&2
  printf '  %s\n' "${FAILURES[@]}" >&2
  exit 1
fi

echo "public tree hygiene ok (${#FILES[@]} files checked)"
