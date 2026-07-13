#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "== focused Thread Sanitizer gate =="
swift test --sanitize=thread \
  --filter '(JobRunnerTests|CoreAudioTapAdapterStateTests|FSEventsArchiveRootWatcherTests|DownloaderViewModelTests)'
