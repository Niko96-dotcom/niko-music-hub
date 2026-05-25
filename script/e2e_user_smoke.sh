#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

FIXTURE_ROOT="$ROOT/Fixtures/CubaseArchive"
SMOKE_SUPPORT="$ROOT/.build/e2e-app-support"
LOG_FILE="$ROOT/.build/e2e-smoke.log"

echo "== generate fixtures =="
./script/fixtures/generate_cubase_archive_fixtures.sh

echo "== build app bundle =="
./script/build_and_run.sh --verify >/dev/null 2>&1 || ./script/build_and_run.sh run >/dev/null 2>&1 || true
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --product NikoMusicHub
BUILD_DIR="$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --show-bin-path)"
APP_BUNDLE="$ROOT/dist/NikoMusicHub.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/NikoMusicHub"
if [[ ! -x "$APP_BINARY" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  cp "$BUILD_DIR/NikoMusicHub" "$APP_BINARY"
  chmod +x "$APP_BINARY"
fi

echo "== reset test Application Support =="
rm -rf "$SMOKE_SUPPORT"
mkdir -p "$SMOKE_SUPPORT"

echo "== archive smoke (CLI hook, not pgrep-only) =="
rm -f "$LOG_FILE"
(
  export NIKO_MUSIC_HUB_E2E_SMOKE=1
  export NIKO_MUSIC_HUB_FIXTURE_ROOT="$FIXTURE_ROOT"
  export NIKO_MUSIC_HUB_DRY_RUN_OPEN=1
  export HOME="$SMOKE_SUPPORT"
  cd "$ROOT"
  "$APP_BINARY"
) 2>&1 | tee "$LOG_FILE"

if ! grep -q "user_flow=scan_search_open" "$LOG_FILE"; then
  echo "E2E failed: view-model user flow marker missing" >&2
  exit 1
fi

if ! grep -q "neon_hook=Neon Hook" "$LOG_FILE"; then
  echo "E2E failed: Neon Hook not found in smoke output" >&2
  exit 1
fi

if ! grep -q "search_query=neon hk" "$LOG_FILE"; then
  echo "E2E failed: fuzzy search query marker missing" >&2
  exit 1
fi

if ! grep -q "search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: Neon Hook search did not narrow to one song" >&2
  exit 1
fi

if ! grep -q "search_match_summary=.*neon" "$LOG_FILE"; then
  echo "E2E failed: search match explainability missing neon token" >&2
  exit 1
fi

if ! grep -q "search_match_summary=.*hk" "$LOG_FILE"; then
  echo "E2E failed: search match explainability missing hk token" >&2
  exit 1
fi

if ! grep -q "preview_rank_summary=.*v3" "$LOG_FILE"; then
  echo "E2E failed: preview ranking explainability missing v3 signal" >&2
  exit 1
fi

if ! grep -q "preview_rank_summary=.*wav" "$LOG_FILE"; then
  echo "E2E failed: preview ranking explainability missing wav signal" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_ranking_match=true" "$LOG_FILE"; then
  echo "E2E failed: preview-ranking diagnostics export missing active match marker" >&2
  exit 1
fi

RANKING_EXPORT_PATH="$(grep -m1 'diagnostics_export_ranking_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_ranking_path=//')"
if [[ -z "$RANKING_EXPORT_PATH" || ! -f "$RANKING_EXPORT_PATH" ]]; then
  echo "E2E failed: preview-ranking diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "selected_song_title=Preview Ranking Lab" "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing selected Preview Ranking Lab song" >&2
  exit 1
fi

if ! grep -q "preview_rank_line=.*v3" "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing preview_rank_line v3 signal" >&2
  exit 1
fi

if ! grep -q "preview_ranking_tiebreak_legend=" "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing preview ranking tiebreak legend" >&2
  exit 1
fi

if ! grep -qE 'too_short_non_main=[1-9][0-9]*' "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing too_short_non_main count" >&2
  exit 1
fi

if ! grep -qE 'songs_with_too_short=[1-9][0-9]*' "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing songs_with_too_short count" >&2
  exit 1
fi

if ! grep -q 'too_short_song=Preview Ranking Lab count=1 clips=Lab Song short clip.wav' "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing per-song too_short breakdown" >&2
  exit 1
fi

if ! grep -q "preview_ranking_scan_callout=" "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing preview ranking scan callout" >&2
  exit 1
fi

if ! grep -q "preview_ranking_selected_header=" "$RANKING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing preview ranking selected header" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_tiebreak_match=true" "$LOG_FILE"; then
  echo "E2E failed: equal-score tiebreak diagnostics export missing active match marker" >&2
  exit 1
fi

TIEBREAK_EXPORT_PATH="$(grep -m1 'diagnostics_export_tiebreak_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_tiebreak_path=//')"
if [[ -z "$TIEBREAK_EXPORT_PATH" || ! -f "$TIEBREAK_EXPORT_PATH" ]]; then
  echo "E2E failed: equal-score tiebreak diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "selected_song_title=Equal Score Tiebreak Lab" "$TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing selected Equal Score Tiebreak Lab song" >&2
  exit 1
fi

if ! grep -q "preview_rank_tiebreak=Equal score — longer preview" "$TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing equal-score preview_rank_tiebreak line" >&2
  exit 1
fi

if ! grep -q "broken_folder_warnings=.*CPR" "$LOG_FILE"; then
  echo "E2E failed: broken folder display warnings missing CPR signal" >&2
  exit 1
fi

if ! grep -q "broken_folder_notes=notes only" "$LOG_FILE"; then
  echo "E2E failed: broken folder sidecar notes missing from smoke output" >&2
  exit 1
fi

if ! grep -q "warning_search_query=project" "$LOG_FILE"; then
  echo "E2E failed: warning search query marker missing" >&2
  exit 1
fi

if ! grep -q "warning_search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: warning search did not narrow to one song" >&2
  exit 1
fi

if ! grep -q "warning_search_match=Broken Folder Example" "$LOG_FILE"; then
  echo "E2E failed: warning search did not select Broken Folder Example" >&2
  exit 1
fi

if ! grep -q "warning_search_summary=.*scan warning" "$LOG_FILE"; then
  echo "E2E failed: warning search explainability missing scan warning signal" >&2
  exit 1
fi

if ! grep -q "warning_search_summary=.*project" "$LOG_FILE"; then
  echo "E2E failed: warning search explainability missing project token" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_warning_match=true" "$LOG_FILE"; then
  echo "E2E failed: warning-search diagnostics export missing active match marker" >&2
  exit 1
fi

if ! grep -q "notes_search_query=nts nly" "$LOG_FILE"; then
  echo "E2E failed: sidecar notes search query marker missing" >&2
  exit 1
fi

if ! grep -q "notes_search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: sidecar notes search did not narrow to one song" >&2
  exit 1
fi

if ! grep -q "notes_search_match=Broken Folder Example" "$LOG_FILE"; then
  echo "E2E failed: sidecar notes search did not select Broken Folder Example" >&2
  exit 1
fi

if ! grep -q "notes_search_summary=.*fuzzy song note" "$LOG_FILE"; then
  echo "E2E failed: sidecar notes search explainability missing fuzzy song note signal" >&2
  exit 1
fi

if ! grep -q "notes_search_summary=.*nts" "$LOG_FILE"; then
  echo "E2E failed: sidecar notes search explainability missing nts token" >&2
  exit 1
fi

if ! grep -q "notes_search_summary=.*nly" "$LOG_FILE"; then
  echo "E2E failed: sidecar notes search explainability missing nly token" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_notes_match=true" "$LOG_FILE"; then
  echo "E2E failed: sidecar-notes diagnostics export missing active match marker" >&2
  exit 1
fi

NOTES_EXPORT_PATH="$(grep -m1 'diagnostics_export_notes_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_notes_path=//')"
if [[ -z "$NOTES_EXPORT_PATH" || ! -f "$NOTES_EXPORT_PATH" ]]; then
  echo "E2E failed: sidecar-notes diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "search_match title=Broken Folder Example" "$NOTES_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing search_match row for sidecar notes search" >&2
  exit 1
fi

if ! grep -q "fuzzy song note" "$NOTES_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing fuzzy song note explainability" >&2
  exit 1
fi

WARNING_EXPORT_PATH="$(grep -m1 'diagnostics_export_warning_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_warning_path=//')"
if [[ -z "$WARNING_EXPORT_PATH" || ! -f "$WARNING_EXPORT_PATH" ]]; then
  echo "E2E failed: warning-search diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "search_match title=Broken Folder Example" "$WARNING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing search_match row for Broken Folder Example" >&2
  exit 1
fi

if ! grep -q "skipped_search_query=LOOSE_FILE.txt" "$LOG_FILE"; then
  echo "E2E failed: skipped-entry search query marker missing" >&2
  exit 1
fi

if ! grep -q "skipped_search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: skipped-entry search did not narrow to one match" >&2
  exit 1
fi

if ! grep -q "skipped_search_label=LOOSE_FILE.txt" "$LOG_FILE"; then
  echo "E2E failed: skipped-entry search did not select LOOSE_FILE.txt" >&2
  exit 1
fi

if ! grep -q "skipped_search_summary=.*skipped label" "$LOG_FILE"; then
  echo "E2E failed: skipped-entry search explainability missing skipped label signal" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_search_match=true" "$LOG_FILE"; then
  echo "E2E failed: song-search diagnostics export missing active match marker" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_summary_match=true" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics summary_line export missing active match marker" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_summary_line=summary_line=roots:" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics summary_line export marker missing from smoke output" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_summary_line=.*Scanned 5 songs" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics summary_line missing song count" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_summary_line=.*2 skipped at roots" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics summary_line missing skipped count" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_matches_export=true" "$LOG_FILE"; then
  echo "E2E failed: diagnostics panel support summary does not match export summary_line" >&2
  exit 1
fi

if ! grep -q "healthy_export_omits_root_health_badge=true" "$LOG_FILE"; then
  echo "E2E failed: healthy fixture export should omit root_health_badge=" >&2
  exit 1
fi

if ! grep -q "healthy_panel_root_health_badge_nil=true" "$LOG_FILE"; then
  echo "E2E failed: healthy fixture panel should not show root health badge" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_invalid_root_badge_match=true" "$LOG_FILE"; then
  echo "E2E failed: invalid-root diagnostics export missing root_health_badge match" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_invalid_root_badge_matches_export=true" "$LOG_FILE"; then
  echo "E2E failed: invalid-root panel badge does not match export root_health_badge" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_root_health_badge_id=archive_diagnostics_root_health_badge" "$LOG_FILE"; then
  echo "E2E failed: diagnostics panel root health badge accessibility id missing from smoke output" >&2
  exit 1
fi

INVALID_ROOT_EXPORT_PATH="$(grep -m1 'diagnostics_export_invalid_root_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_invalid_root_path=//')"
if [[ -z "$INVALID_ROOT_EXPORT_PATH" || ! -f "$INVALID_ROOT_EXPORT_PATH" ]]; then
  echo "E2E failed: invalid-root diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "root_health_badge=.*invalid root" "$INVALID_ROOT_EXPORT_PATH"; then
  echo "E2E failed: invalid-root export missing root_health_badge invalid root signal" >&2
  exit 1
fi

if ! grep -q "root_health_badge=.*root warning" "$INVALID_ROOT_EXPORT_PATH"; then
  echo "E2E failed: invalid-root export missing root_health_badge root warning signal" >&2
  exit 1
fi

PANEL_INVALID_ROOT_BADGE="$(grep -m1 'diagnostics_panel_invalid_root_badge=' "$LOG_FILE" | sed 's/.*diagnostics_panel_invalid_root_badge=//')"
if [[ -z "$PANEL_INVALID_ROOT_BADGE" ]]; then
  echo "E2E failed: invalid-root panel badge missing from smoke output" >&2
  exit 1
fi

if ! grep -q "root_health_badge=${PANEL_INVALID_ROOT_BADGE}" "$INVALID_ROOT_EXPORT_PATH"; then
  echo "E2E failed: export root_health_badge does not match panel badge text" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_support_summary=roots:" "$LOG_FILE"; then
  echo "E2E failed: diagnostics panel support summary missing roots prefix" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_support_summary=.*Scanned 5 songs" "$LOG_FILE"; then
  echo "E2E failed: diagnostics panel support summary missing song count" >&2
  exit 1
fi

SEARCH_EXPORT_PATH="$(grep -m1 'diagnostics_export_search_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_search_path=//')"
if [[ -z "$SEARCH_EXPORT_PATH" || ! -f "$SEARCH_EXPORT_PATH" ]]; then
  echo "E2E failed: song-search diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "search_match title=Neon Hook" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing search_match row for Neon Hook" >&2
  exit 1
fi

if ! grep -q "summary_line=roots:" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line roots prefix" >&2
  exit 1
fi

if ! grep -q "summary_line=.*Scanned 5 songs" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line song count" >&2
  exit 1
fi

if ! grep -q "summary_line=.*1 song(s) with 1 warning(s)" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line warning count" >&2
  exit 1
fi

if ! grep -q "summary_line=.*2 skipped at roots" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line skipped count" >&2
  exit 1
fi

if grep -q "root_health_badge=" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: healthy fixture export must omit root_health_badge=" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_skipped_match=true" "$LOG_FILE"; then
  echo "E2E failed: skipped-search diagnostics export missing active match marker" >&2
  exit 1
fi

EXPORT_PATH="$(grep -m1 'diagnostics_export_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_path=//')"
if [[ -z "$EXPORT_PATH" || ! -f "$EXPORT_PATH" ]]; then
  echo "E2E failed: diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "skipped_search_match label=LOOSE_FILE.txt" "$EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing skipped_search_match row" >&2
  exit 1
fi

if ! grep -q "diagnostics_songs=" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics song count missing" >&2
  exit 1
fi

if ! grep -q "diagnostics_skipped=" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics skipped count missing" >&2
  exit 1
fi

if ! grep -q "Neon Hook/Neon Hook.cpr" "$LOG_FILE"; then
  echo "E2E failed: expected dry-run CPR path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "\[dry-run\] open CPR:" "$LOG_FILE"; then
  echo "E2E failed: dry-run open log line missing" >&2
  exit 1
fi

if ! grep -q "write_probe_denied=true" "$LOG_FILE"; then
  echo "E2E failed: read-only write probe not reported" >&2
  exit 1
fi

if ! grep -q "archive_unchanged=true" "$LOG_FILE"; then
  echo "E2E failed: fixture archive tree changed during smoke" >&2
  exit 1
fi

if ! grep -q "\[niko-music-hub-smoke\] ok" "$LOG_FILE"; then
  echo "E2E failed: smoke did not report ok" >&2
  exit 1
fi

echo "E2E user smoke passed."
