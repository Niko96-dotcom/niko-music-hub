#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIN_MACOS="14.2"
DEV_FLOW_LOG_DIR="$ROOT_DIR/.build/dev-flow"

FAILURES=0
WARNINGS=0

cd "$ROOT_DIR"

print_bold() {
  if [[ -t 1 ]]; then
    printf '\033[1m%s\033[0m\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

section() {
  printf '\n'
  print_bold "$*"
}

ok() {
  printf '[OK] %s\n' "$*"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s\n' "$*"
}

command_path() {
  command -v "$1" 2>/dev/null || true
}

version_ge() {
  /usr/bin/awk -v current="$1" -v required="$2" '
    BEGIN {
      split(current, c, ".")
      split(required, r, ".")
      for (i = 1; i <= 3; i++) {
        cv = (c[i] == "" ? 0 : c[i]) + 0
        rv = (r[i] == "" ? 0 : r[i]) + 0
        if (cv > rv) exit 0
        if (cv < rv) exit 1
      }
      exit 0
    }
  '
}

require_command() {
  local label="$1"
  local executable="$2"
  local path
  path="$(command_path "$executable")"
  if [[ -n "$path" ]]; then
    ok "$label: $path"
  else
    fail "$label is missing. Install Xcode or Command Line Tools, then rerun doctor."
  fi
}

optional_command() {
  local label="$1"
  local executable="$2"
  local hint="$3"
  local path
  path="$(command_path "$executable")"
  if [[ -n "$path" ]]; then
    ok "$label: $path"
  else
    warn "$label is missing. $hint"
  fi
}

check_script() {
  local script_path="$1"
  if [[ -x "$script_path" ]]; then
    ok "$script_path is executable"
  elif [[ -f "$script_path" ]]; then
    fail "$script_path exists but is not executable"
  else
    fail "$script_path is missing"
  fi
}

check_ignored() {
  local generated_path="$1"
  if git check-ignore -q "$generated_path" 2>/dev/null; then
    ok "$generated_path is ignored by git"
  else
    warn "$generated_path is not ignored by git"
  fi
}

run_step() {
  local title="$1"
  shift
  section "$title"
  "$@"
}

run_logged_step() {
  local title="$1"
  local log_file="$2"
  shift 2

  section "$title"
  printf 'Running: %s\n' "$*"
  printf 'Log: %s\n' "$log_file"

  local status=0
  "$@" >"$log_file" 2>&1 || status=$?

  if [[ "$status" -eq 0 ]]; then
    ok "$title passed"
    return 0
  fi

  fail "$title failed with exit code $status"
  printf '\nLast log lines:\n'
  tail -n 80 "$log_file" || true
  return "$status"
}

show_help() {
  cat <<'HELP'
Niko Music Hub local dev flow

Most useful:
  ./script/dev.sh run       Build a fresh app bundle and open it.
  ./script/dev.sh check     Run the full local truth: CI, E2E smoke, visible launch.
  ./script/dev.sh doctor    Check whether this Mac/repo is ready.

Helpful when something is weird:
  ./script/dev.sh logs      Build, open, then stream app logs.
  ./script/dev.sh proof     Save visible-window screenshots into dist/.
  ./script/dev.sh stop      Stop any running Niko Music Hub instance.
  ./script/dev.sh clean     Delete generated build output.
  ./script/dev.sh helpers   Install/update ffmpeg and yt-dlp with Homebrew.
  ./script/dev.sh live-downloader  Opt-in real yt-dlp smoke (needs NIKO_MUSIC_HUB_LIVE_DOWNLOADER=1).

Finder shortcuts:
  Double-click "Run Niko Music Hub.command" to build and launch.
  Double-click "Check Niko Music Hub.command" to run the full local check.
HELP
}

doctor() {
  FAILURES=0
  WARNINGS=0

  section "System"
  local macos
  macos="$(sw_vers -productVersion 2>/dev/null || true)"
  if [[ -n "$macos" ]] && version_ge "$macos" "$MIN_MACOS"; then
    ok "macOS $macos (minimum $MIN_MACOS)"
  elif [[ -n "$macos" ]]; then
    fail "macOS $macos is older than the required $MIN_MACOS"
  else
    fail "Could not read macOS version"
  fi

  require_command "Swift" swift
  local swift_version
  swift_version="$(swift --version 2>/dev/null | head -n 1 || true)"
  if [[ "$swift_version" == *"Swift version 6"* ]]; then
    ok "$swift_version"
  elif [[ -n "$swift_version" ]]; then
    warn "$swift_version (project expects Swift 6.x)"
  fi

  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -n "$developer_dir" ]]; then
    ok "Developer tools: $developer_dir"
  else
    fail "Xcode developer tools are not selected. Run xcode-select --install or install Xcode."
  fi

  if [[ -d /Applications/Xcode.app ]]; then
    ok "Full Xcode.app is installed"
  else
    warn "Full /Applications/Xcode.app was not found. Command Line Tools may still build, but Xcode UI workflows will not."
  fi

  section "Repository"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "Git repository detected"
  else
    fail "This folder is not inside a git repository"
  fi

  if [[ -f Package.swift ]]; then
    ok "Package.swift found"
  else
    fail "Package.swift is missing"
  fi

  if swift package describe --type json >/dev/null 2>&1; then
    ok "Swift package manifest parses"
  else
    fail "Swift package manifest does not parse"
  fi

  check_script ./script/build_and_run.sh
  check_script ./script/ci.sh
  check_script ./script/e2e_user_smoke.sh
  check_script ./script/downloader_live_smoke.sh
  check_script ./script/capture_window_proof.sh

  if [[ -f .codex/environments/environment.toml ]] &&
    grep -Fq 'command = "./script/build_and_run.sh"' .codex/environments/environment.toml; then
    ok "Codex Run button points at ./script/build_and_run.sh"
  else
    warn "Codex Run button config is missing or points somewhere unexpected"
  fi

  check_ignored .build/
  check_ignored dist/
  check_ignored DerivedData/
  check_ignored .DS_Store
  check_ignored .ai/runs/

  section "Helper Tools"
  optional_command "ffmpeg" ffmpeg "Needed for full audio conversion workflows. Run ./script/dev.sh helpers to install it."
  optional_command "yt-dlp" yt-dlp "Needed for downloader workflows. Run ./script/dev.sh helpers to install it."
  optional_command "Homebrew" brew "Needed only if you want ./script/dev.sh helpers to install helper tools for you."

  section "Outcome"
  if [[ "$FAILURES" -gt 0 ]]; then
    fail "$FAILURES required check(s) failed; fix those before trusting local builds"
    return 1
  fi

  if [[ "$WARNINGS" -gt 0 ]]; then
    warn "Doctor passed with $WARNINGS warning(s)"
  else
    ok "Doctor passed with no warnings"
  fi
}

install_helpers() {
  local brew_path
  brew_path="$(command_path brew)"
  if [[ -z "$brew_path" ]]; then
    printf 'Homebrew is not installed. Install it from https://brew.sh, then rerun ./script/dev.sh helpers\n' >&2
    return 1
  fi

  section "Homebrew Helpers"
  "$brew_path" update
  for package in ffmpeg yt-dlp; do
    if "$brew_path" list --versions "$package" >/dev/null 2>&1; then
      "$brew_path" upgrade "$package" || true
    else
      "$brew_path" install "$package"
    fi
  done
  doctor
}

full_check() {
  doctor
  mkdir -p "$DEV_FLOW_LOG_DIR"
  run_logged_step "1/3 Compile and unit tests" "$DEV_FLOW_LOG_DIR/ci.log" ./script/ci.sh
  run_logged_step "2/3 User E2E smoke" "$DEV_FLOW_LOG_DIR/e2e_user_smoke.log" ./script/e2e_user_smoke.sh
  run_logged_step "3/3 Visible launch verification" "$DEV_FLOW_LOG_DIR/build_and_run_verify.log" ./script/build_and_run.sh --verify
  section "Done"
  ok "Local dev flow is green"
  printf 'Logs: %s\n' "$DEV_FLOW_LOG_DIR"
}

stop_app() {
  # shellcheck source=lib/app_lifecycle.sh
  source "$ROOT_DIR/script/lib/app_lifecycle.sh"
  nmh_stop_app true
  ok "Stopped Niko Music Hub if it was running"
}

case "${1:-help}" in
  help|-h|--help)
    show_help
    ;;
  run|start|open)
    ./script/build_and_run.sh
    ;;
  check|verify|all)
    full_check
    ;;
  doctor)
    doctor
    ;;
  smoke)
    ./script/e2e_user_smoke.sh
    ;;
  live-downloader)
    NIKO_MUSIC_HUB_LIVE_DOWNLOADER="${NIKO_MUSIC_HUB_LIVE_DOWNLOADER:-1}" ./script/downloader_live_smoke.sh
    ;;
  logs)
    ./script/build_and_run.sh --logs
    ;;
  telemetry)
    ./script/build_and_run.sh --telemetry
    ;;
  proof)
    ./script/capture_window_proof.sh
    ;;
  stop)
    stop_app
    ;;
  clean)
    section "Cleaning Generated Output"
    rm -rf "$ROOT_DIR/.build" "$ROOT_DIR/dist" "$ROOT_DIR/DerivedData"
    ok "Removed .build, dist, and DerivedData"
    ;;
  helpers)
    install_helpers
    ;;
  *)
    show_help
    printf '\nUnknown command: %s\n' "$1" >&2
    exit 2
    ;;
esac
