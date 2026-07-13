#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCLUDE_UNTRACKED=false

usage() {
  cat >&2 <<'USAGE'
usage: script/public-tree-hygiene.sh [--include-untracked]

Checks the public/tracked tree for release-hostile files and credential-shaped
content. --include-untracked performs a stricter local sweep.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-untracked) INCLUDE_UNTRACKED=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

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
done

if [[ -n "${NMH_PUBLIC_TREE_STRICT_PLANNING:-}" ]]; then
  for file in "${FILES[@]}"; do
    case "$file" in
      .planning/*) FAILURES+=("$file: strict public release mode forbids planning archive files") ;;
    esac
  done
fi

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

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "public tree hygiene failed:" >&2
  printf '  %s\n' "${FAILURES[@]}" >&2
  exit 1
fi

echo "public tree hygiene ok (${#FILES[@]} files checked)"
