#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/app_lifecycle.sh
source "$ROOT_DIR/script/lib/app_lifecycle.sh"

MODE="${1:-run}"

cd "$NMH_ROOT_DIR"

nmh_stop_app
nmh_build_bundle

case "$MODE" in
  run)
    nmh_open_app
    echo "Launched $NMH_APP_BUNDLE"
    echo "If nothing appears: Force Quit old Niko Music Hub instances, then rerun."
    echo "First Finder open of dist/NikoMusicHub.app may need Right-click → Open."
    ;;
  --debug|debug)
    lldb -- "$NMH_APP_BINARY"
    ;;
  --logs|logs)
    nmh_open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$NMH_APP_NAME\""
    ;;
  --telemetry|telemetry)
    nmh_open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$NMH_BUNDLE_ID\""
    ;;
  --verify|verify)
    nmh_open_app
    sleep "$NMH_LAUNCH_WAIT_SEC"
    /usr/bin/pgrep -x "$NMH_APP_NAME" >/dev/null
    VERIFY_STATUS=0
    nmh_ui_probe \
      --binary-path "$NMH_APP_BINARY" \
      --check-visible || VERIFY_STATUS=$?
    case "$VERIFY_STATUS" in
      0) echo "verify ok: visible main window" ;;
      2) echo "verify skipped: AX/window check unavailable" ;;
      3) echo "verify failed: $NMH_APP_NAME did not launch from $NMH_APP_BINARY" >&2; exit 1 ;;
      *) echo "verify failed: $NMH_APP_NAME is running but has no visible main window" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
