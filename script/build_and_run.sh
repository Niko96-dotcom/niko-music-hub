#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--verify-isolated) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-isolated]" >&2; exit 2 ;;
esac

if [[ "$MODE" == "--verify-isolated" ]]; then
  mkdir -p "$ROOT_DIR/.build/dev-flow"
  STARTUP_EVIDENCE="$(mktemp -d "$ROOT_DIR/.build/dev-flow/startup.XXXXXX")"
  STARTUP_SUITE="NikoMusicHubStartup.$(uuidgen)"
  # A separate bundle keeps verification from stopping the user's dev app.
  export NMH_DIST_DIR="$ROOT_DIR/dist/verification"
  # Do not inherit real roots or special launch hooks from the caller.
  while IFS= read -r variable; do
    unset "$variable"
  done < <(compgen -v NIKO_MUSIC_HUB_)
  export NIKO_MUSIC_HUB_SETTINGS_SUITE="$STARTUP_SUITE"
  export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
  printf 'Startup evidence: %s\nSettings suite: %s\n' "$STARTUP_EVIDENCE" "$STARTUP_SUITE"
fi

# shellcheck source=lib/app_lifecycle.sh
source "$ROOT_DIR/script/lib/app_lifecycle.sh"

if [[ "$MODE" == "--verify-isolated" ]]; then
  cleanup_startup() {
    # Do not remove state while its process could still be writing it.
    nmh_stop_app true || return 1
    nmh_forget_settings_suite "$STARTUP_SUITE"
    rm -rf "$HOME/Library/Application Support/Niko Music Hub/Isolated/$STARTUP_SUITE"
  }
  trap cleanup_startup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi

cd "$NMH_ROOT_DIR"

nmh_stop_app true
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
  --verify-isolated)
    nmh_open_app --stdout "$STARTUP_EVIDENCE/stdout.log" --stderr "$STARTUP_EVIDENCE/stderr.log" --env NSUnbufferedIO=YES
    STARTUP_DEADLINE=$((SECONDS + 20))
    STARTUP_READY=false
    while (( SECONDS < STARTUP_DEADLINE )); do
      STARTUP_PID="$(nmh_running_dist_app_pids | head -n 1)"
      if [[ -n "$STARTUP_PID" ]]; then
        PROBE_STATUS=0
        nmh_ui_probe --pid "$STARTUP_PID" --binary-path "$NMH_APP_BINARY" \
          --check-visible >"$STARTUP_EVIDENCE/window.txt" 2>&1 || PROBE_STATUS=$?
        case "$PROBE_STATUS" in
          0) STARTUP_READY=true; break ;;
          2|3) break ;; # Missing API access or wrong binary cannot prove startup.
        esac
      fi
      sleep 1
    done
    if [[ "$STARTUP_READY" != true ]]; then
      echo "verify failed: isolated app has no verified visible window; inspect $STARTUP_EVIDENCE" >&2
      exit 1
    fi
    nmh_ui_probe --pid "$STARTUP_PID" --binary-path "$NMH_APP_BINARY" \
      --ax-dump >"$STARTUP_EVIDENCE/accessibility.txt" 2>"$STARTUP_EVIDENCE/accessibility-error.log" || true
    echo "verify ok: isolated visible main window (pid=$STARTUP_PID)"
    ;;
esac
