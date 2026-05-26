#!/usr/bin/env bash
# Clone or update Niko Music Hub at /Users/niko/Documents/Niko-Music-Hub and run local gates.
set -euo pipefail

TARGET="${NIKO_MUSIC_HUB_REPO:-/Users/niko/Documents/Niko-Music-Hub}"
REPO_URL="${NIKO_MUSIC_HUB_REPO_URL:-https://github.com/Niko96-dotcom/niko-music-hub.git}"
BRANCH="${1:-main}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Run this on your Mac (found: $(uname -s))." >&2
  exit 1
fi

if [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
  echo "Refusing to use non-directory path: $TARGET" >&2
  exit 1
fi

checkout_branch() {
  local repo="$1"
  local branch="$2"
  git -C "$repo" fetch origin
  if git -C "$repo" rev-parse --verify "refs/remotes/origin/$branch" >/dev/null 2>&1; then
    git -C "$repo" checkout "$branch" 2>/dev/null || git -C "$repo" checkout -B "$branch" "origin/$branch"
    git -C "$repo" reset --hard "origin/$branch"
  else
    git -C "$repo" checkout "$branch"
    git -C "$repo" pull --ff-only origin "$branch" || git -C "$repo" pull origin "$branch"
  fi
}

if [[ -d "$TARGET/.git" ]]; then
  echo "Updating existing repo at $TARGET (branch $BRANCH)"
  checkout_branch "$TARGET" "$BRANCH"
elif [[ -d "$TARGET" ]]; then
  if [[ -n "$(ls -A "$TARGET" 2>/dev/null || true)" ]]; then
    echo "$TARGET exists but is not a git checkout. Move it aside or set NIKO_MUSIC_HUB_REPO." >&2
    exit 1
  fi
  rmdir "$TARGET"
  mkdir -p "$(dirname "$TARGET")"
  echo "Cloning into $TARGET (branch $BRANCH)"
  git clone --branch "$BRANCH" "$REPO_URL" "$TARGET" || {
    git clone "$REPO_URL" "$TARGET"
    checkout_branch "$TARGET" "$BRANCH"
  }
else
  mkdir -p "$(dirname "$TARGET")"
  echo "Cloning into $TARGET (branch $BRANCH)"
  git clone --branch "$BRANCH" "$REPO_URL" "$TARGET" || {
    git clone "$REPO_URL" "$TARGET"
    checkout_branch "$TARGET" "$BRANCH"
  }
fi

cd "$TARGET"

if [[ ! -x script/setup_mac_check.sh ]]; then
  echo "Checkout at $TARGET is missing script/setup_mac_check.sh — wrong branch?" >&2
  exit 1
fi

./script/setup_mac_check.sh
./script/fixtures/generate_cubase_archive_fixtures.sh
./script/ci.sh
swift build
./script/build_and_run.sh --verify

echo
echo "Ready: $TARGET"
echo "Open in Cursor: cursor \"$TARGET\""
