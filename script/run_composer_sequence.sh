#!/usr/bin/env bash
set -u

REPO="/Users/nikolaymohr/src/niko-music-hub"
ROOT="/Users/nikolaymohr/.hermes/workers/niko-music-hub-composer"
LOCK="/tmp/niko-music-hub-composer.lock"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$ROOT/runs/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
STATUS_DIR="$RUN_DIR/status"
SESSION_DIR="$RUN_DIR/pi-sessions"
SUMMARY="$RUN_DIR/summary.md"
PATH_PREFIX="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$ROOT" "$LOG_DIR" "$STATUS_DIR" "$SESSION_DIR"
printf '%s\n' "$RUN_DIR" > "$ROOT/latest_run.txt"

status_json() {
  state="$1"
  phase="$2"
  code="$3"
  message="$4"
  /usr/bin/python3 - "$ROOT/state.json" "$RUN_DIR" "$state" "$phase" "$code" "$message" <<'PY'
import json, sys, datetime
path, run_dir, state, phase, code, message = sys.argv[1:]
data = {
    "updated_utc": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
    "workflow": "niko-music-hub-composer",
    "state": state,
    "phase": phase,
    "exit_code": int(code),
    "message": message,
    "run_dir": run_dir,
    "repo": "/Users/nikolaymohr/src/niko-music-hub",
}
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
open(f"{run_dir}/status/latest.json", "w", encoding="utf-8").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

finish() {
  rc="$?"
  if [ "$rc" -eq 0 ]; then
    status_json completed done 0 "Composer sequence completed."
  else
    status_json failed failed "$rc" "Composer sequence failed; see run logs."
  fi
  rm -rf "$LOCK"
  exit "$rc"
}
trap finish EXIT INT TERM

if ! mkdir "$LOCK" 2>/dev/null; then
  existing_pid="$(cat "$LOCK/pid" 2>/dev/null || true)"
  echo "Another Niko Music Hub Composer run is already locked (PID: ${existing_pid:-unknown})." >&2
  status_json failed lock 11 "Duplicate composer run refused."
  exit 11
fi
printf '%s\n' "$$" > "$LOCK/pid"
printf '%s\n' "$RUN_DIR" > "$LOCK/run_dir"

cd "$REPO" || exit 2

status_json running bootstrap 0 "Composer sequence starting."
{
  echo "# Niko Music Hub Composer 2.5 sequence"
  echo
  echo "Run ID: $RUN_ID"
  echo "Repo: $REPO"
  echo "Model: cursor/composer-2.5"
  echo "Started UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Initial git status"
  echo '```'
  git status --short --branch
  echo '```'
  echo
} > "$SUMMARY"

rc=0
for prompt in .ai/prompts/01-planner.md .ai/prompts/02-critic.md .ai/prompts/03-executor.md .ai/prompts/04-reviewer.md; do
  task="$(basename "$prompt" .md)"
  log="$LOG_DIR/$task.log"
  status_json running "$task" 0 "Running $task through Pi Composer 2.5."
  echo "===== START $task $(date -u +%Y-%m-%dT%H:%M:%SZ) =====" | tee "$log"
  git status --short --branch > "$STATUS_DIR/$task.before.txt" 2>&1

  set +e
  nice -n 10 env -i \
    HOME="$HOME" \
    USER="${USER:-nikolaymohr}" \
    LOGNAME="${LOGNAME:-nikolaymohr}" \
    SHELL="/bin/zsh" \
    TMPDIR="${TMPDIR:-/tmp}" \
    TERM="${TERM:-xterm-256color}" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH="$PATH_PREFIX" \
    GIT_TERMINAL_PROMPT=0 \
    pi --provider cursor --model composer-2.5 \
      --session-dir "$SESSION_DIR" \
      --tools read,bash,edit,write,grep,find,ls \
      -p @"$REPO/$prompt" 2>&1 | tee -a "$log"
  cmd_rc=${PIPESTATUS[0]}
  set -u

  git status --short --branch > "$STATUS_DIR/$task.after.txt" 2>&1
  git diff --stat > "$STATUS_DIR/$task.diffstat.txt" 2>&1
  {
    echo "## $task"
    echo
    echo "Exit code: $cmd_rc"
    echo "Log: $log"
    echo "Status before: $STATUS_DIR/$task.before.txt"
    echo "Status after: $STATUS_DIR/$task.after.txt"
    echo "Diff stat: $STATUS_DIR/$task.diffstat.txt"
    echo
  } >> "$SUMMARY"
  echo "===== END $task exit=$cmd_rc $(date -u +%Y-%m-%dT%H:%M:%SZ) =====" | tee -a "$log"
  if [ "$cmd_rc" -ne 0 ]; then
    rc="$cmd_rc"
    status_json failed "$task" "$rc" "Pi failed during $task."
    break
  fi

done

if [ "$rc" -eq 0 ]; then
  status_json running final-ci 0 "Running final local gates."
  for check in "./script/ci.sh" "./script/e2e_user_smoke.sh"; do
    safe="$(echo "$check" | tr ' /' '__' | tr -cd '[:alnum:]_.-')"
    log="$LOG_DIR/final-${safe}.log"
    echo "===== FINAL VERIFY $check =====" | tee "$log"
    set +e
    bash -lc "$check" 2>&1 | tee -a "$log"
    check_rc=${PIPESTATUS[0]}
    set -u
    echo "- \`$check\`: exit $check_rc, log $log" >> "$SUMMARY"
    if [ "$check_rc" -ne 0 ]; then
      rc="$check_rc"
      status_json failed final-ci "$rc" "Final gate failed: $check."
      break
    fi
  done
fi

{
  echo
  echo "## Final git status"
  echo '```'
  git status --short --branch
  echo '```'
  echo
  echo "## Recent commits"
  echo '```'
  git log --oneline -10
  echo '```'
  echo
  echo "Finished UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Overall exit code: $rc"
} >> "$SUMMARY"

exit "$rc"
