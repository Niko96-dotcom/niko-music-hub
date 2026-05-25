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

if ! grep -q "selected_song_title=Equal Score Duration Tiebreak" "$TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing selected Equal Score Duration Tiebreak song" >&2
  exit 1
fi

if ! grep -q "preview_rank_tiebreak=Equal score — longer preview" "$TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing equal-score preview_rank_tiebreak line" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_duration_tiebreak_header_match=true" "$LOG_FILE"; then
  echo "E2E failed: duration tiebreak panel header missing export parity marker" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_duration_tiebreak_callout_match=true" "$LOG_FILE"; then
  echo "E2E failed: duration tiebreak panel callout missing export parity marker" >&2
  exit 1
fi

PANEL_DURATION_TIEBREAK_CALLOUT="$(grep -m1 'diagnostics_panel_duration_tiebreak_callout=' "$LOG_FILE" | sed 's/.*diagnostics_panel_duration_tiebreak_callout=//')"
if [[ -z "$PANEL_DURATION_TIEBREAK_CALLOUT" ]]; then
  echo "E2E failed: duration tiebreak panel callout missing from smoke output" >&2
  exit 1
fi

if ! grep -q "preview_rank_tiebreak=${PANEL_DURATION_TIEBREAK_CALLOUT}" "$TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: export preview_rank_tiebreak does not match panel callout" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_preview_tiebreak_id=archive_diagnostics_preview_tiebreak_callout" "$LOG_FILE"; then
  echo "E2E failed: diagnostics panel preview tiebreak accessibility id missing from smoke output" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_version_tiebreak_match=true" "$LOG_FILE"; then
  echo "E2E failed: version tiebreak diagnostics export missing active match marker" >&2
  exit 1
fi

VERSION_TIEBREAK_EXPORT_PATH="$(grep -m1 'diagnostics_export_version_tiebreak_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_version_tiebreak_path=//')"
if [[ -z "$VERSION_TIEBREAK_EXPORT_PATH" || ! -f "$VERSION_TIEBREAK_EXPORT_PATH" ]]; then
  echo "E2E failed: version tiebreak diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "selected_song_title=Equal Score Version Tiebreak" "$VERSION_TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing selected Equal Score Version Tiebreak song" >&2
  exit 1
fi

if ! grep -q "preview_rank_tiebreak=Equal score — version v3 beat v2" "$VERSION_TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing version preview_rank_tiebreak line" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_extension_tiebreak_match=true" "$LOG_FILE"; then
  echo "E2E failed: extension tiebreak diagnostics export missing active match marker" >&2
  exit 1
fi

EXTENSION_TIEBREAK_EXPORT_PATH="$(grep -m1 'diagnostics_export_extension_tiebreak_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_extension_tiebreak_path=//')"
if [[ -z "$EXTENSION_TIEBREAK_EXPORT_PATH" || ! -f "$EXTENSION_TIEBREAK_EXPORT_PATH" ]]; then
  echo "E2E failed: extension tiebreak diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "selected_song_title=Equal Score Extension Tiebreak" "$EXTENSION_TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing selected Equal Score Extension Tiebreak song" >&2
  exit 1
fi

if ! grep -q "preview_rank_tiebreak=Equal score — preferred flac over mp3" "$EXTENSION_TIEBREAK_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing extension preview_rank_tiebreak line" >&2
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

if ! grep -q "fuzzy_warning_search_query=ncpr fnd" "$LOG_FILE"; then
  echo "E2E failed: fuzzy scan warning search query marker missing" >&2
  exit 1
fi

if ! grep -q "fuzzy_warning_search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: fuzzy scan warning search did not narrow to one song" >&2
  exit 1
fi

if ! grep -q "fuzzy_warning_search_match=Broken Folder Example" "$LOG_FILE"; then
  echo "E2E failed: fuzzy scan warning search did not select Broken Folder Example" >&2
  exit 1
fi

if ! grep -q "fuzzy_warning_search_summary=.*fuzzy scan warning" "$LOG_FILE"; then
  echo "E2E failed: fuzzy scan warning search explainability missing fuzzy scan warning signal" >&2
  exit 1
fi

if ! grep -q "fuzzy_warning_search_summary=.*ncpr" "$LOG_FILE"; then
  echo "E2E failed: fuzzy scan warning search explainability missing ncpr token" >&2
  exit 1
fi

if ! grep -q "fuzzy_warning_search_summary=.*fnd" "$LOG_FILE"; then
  echo "E2E failed: fuzzy scan warning search explainability missing fnd token" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_fuzzy_warning_match=true" "$LOG_FILE"; then
  echo "E2E failed: fuzzy scan-warning diagnostics export missing active match marker" >&2
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

if ! grep -q "folder_search_query=brkn fld" "$LOG_FILE"; then
  echo "E2E failed: fuzzy folder search query marker missing" >&2
  exit 1
fi

if ! grep -q "folder_search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: fuzzy folder search did not narrow to one song" >&2
  exit 1
fi

if ! grep -q "folder_search_match=Broken Folder Example" "$LOG_FILE"; then
  echo "E2E failed: fuzzy folder search did not select Broken Folder Example" >&2
  exit 1
fi

if ! grep -q "folder_search_summary=.*fuzzy folder" "$LOG_FILE"; then
  echo "E2E failed: fuzzy folder search explainability missing fuzzy folder signal" >&2
  exit 1
fi

if ! grep -q "folder_search_summary=.*brkn" "$LOG_FILE"; then
  echo "E2E failed: fuzzy folder search explainability missing brkn token" >&2
  exit 1
fi

if ! grep -q "folder_search_summary=.*fld" "$LOG_FILE"; then
  echo "E2E failed: fuzzy folder search explainability missing fld token" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_folder_match=true" "$LOG_FILE"; then
  echo "E2E failed: fuzzy-folder diagnostics export missing active match marker" >&2
  exit 1
fi

FOLDER_EXPORT_PATH="$(grep -m1 'diagnostics_export_folder_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_folder_path=//')"
if [[ -z "$FOLDER_EXPORT_PATH" || ! -f "$FOLDER_EXPORT_PATH" ]]; then
  echo "E2E failed: fuzzy-folder diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "search_match title=Broken Folder Example" "$FOLDER_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing search_match row for fuzzy folder search" >&2
  exit 1
fi

if ! grep -q "fuzzy folder" "$FOLDER_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing fuzzy folder explainability" >&2
  exit 1
fi

if ! grep -q "cpr_search_query=neohkv2" "$LOG_FILE"; then
  echo "E2E failed: fuzzy CPR search query marker missing" >&2
  exit 1
fi

if ! grep -q "cpr_search_matches=1" "$LOG_FILE"; then
  echo "E2E failed: fuzzy CPR search did not narrow to one song" >&2
  exit 1
fi

if ! grep -q "cpr_search_match=Neon Hook" "$LOG_FILE"; then
  echo "E2E failed: fuzzy CPR search did not select Neon Hook" >&2
  exit 1
fi

if ! grep -q "cpr_search_summary=.*fuzzy CPR file" "$LOG_FILE"; then
  echo "E2E failed: fuzzy CPR search explainability missing fuzzy CPR file signal" >&2
  exit 1
fi

if ! grep -q "cpr_search_summary=.*neohkv2" "$LOG_FILE"; then
  echo "E2E failed: fuzzy CPR search explainability missing neohkv2 token" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_cpr_match=true" "$LOG_FILE"; then
  echo "E2E failed: fuzzy-CPR diagnostics export missing active match marker" >&2
  exit 1
fi

CPR_EXPORT_PATH="$(grep -m1 'diagnostics_export_cpr_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_cpr_path=//')"
if [[ -z "$CPR_EXPORT_PATH" || ! -f "$CPR_EXPORT_PATH" ]]; then
  echo "E2E failed: fuzzy-CPR diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "search_match title=Neon Hook" "$CPR_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing search_match row for fuzzy CPR search" >&2
  exit 1
fi

if ! grep -q "fuzzy CPR file" "$CPR_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing fuzzy CPR file explainability" >&2
  exit 1
fi

if ! grep -q "preview_search_query=ranking lab v3 mx" "$LOG_FILE"; then
  echo "E2E failed: fuzzy preview search query marker missing" >&2
  exit 1
fi

if ! grep -q "preview_search_match=Preview Ranking Lab" "$LOG_FILE"; then
  echo "E2E failed: fuzzy preview search did not select Preview Ranking Lab" >&2
  exit 1
fi

if ! grep -q "preview_search_summary=.*fuzzy preview file" "$LOG_FILE"; then
  echo "E2E failed: fuzzy preview search explainability missing fuzzy preview file signal" >&2
  exit 1
fi

if ! grep -q "preview_search_summary=.*v3" "$LOG_FILE"; then
  echo "E2E failed: fuzzy preview search explainability missing v3 token" >&2
  exit 1
fi

if ! grep -q "preview_search_summary=.*mx" "$LOG_FILE"; then
  echo "E2E failed: fuzzy preview search explainability missing mx token" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_preview_match=true" "$LOG_FILE"; then
  echo "E2E failed: fuzzy-preview diagnostics export missing active match marker" >&2
  exit 1
fi

PREVIEW_EXPORT_PATH="$(grep -m1 'diagnostics_export_preview_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_preview_path=//')"
if [[ -z "$PREVIEW_EXPORT_PATH" || ! -f "$PREVIEW_EXPORT_PATH" ]]; then
  echo "E2E failed: fuzzy-preview diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "search_match title=Preview Ranking Lab" "$PREVIEW_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing search_match row for fuzzy preview search" >&2
  exit 1
fi

if ! grep -q "fuzzy preview file" "$PREVIEW_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing fuzzy preview file explainability" >&2
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

FUZZY_WARNING_EXPORT_PATH="$(grep -m1 'diagnostics_export_fuzzy_warning_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_fuzzy_warning_path=//')"
if [[ -z "$FUZZY_WARNING_EXPORT_PATH" || ! -f "$FUZZY_WARNING_EXPORT_PATH" ]]; then
  echo "E2E failed: fuzzy scan-warning diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "search_match title=Broken Folder Example" "$FUZZY_WARNING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing fuzzy scan-warning search_match row" >&2
  exit 1
fi

if ! grep -q "fuzzy scan warning" "$FUZZY_WARNING_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing fuzzy scan warning explainability" >&2
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

if ! grep -q "diagnostics_export_summary_line=.*Scanned 7 songs" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics summary_line missing song count" >&2
  exit 1
fi

if ! grep -q "diagnostics_export_summary_line=.*Broken Folder Example" "$LOG_FILE"; then
  echo "E2E failed: scan diagnostics summary_line missing song warning titles" >&2
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

FIXTURE_SCAN_HEALTH_BADGE="$(grep -m1 'fixture_scan_health_badge=' "$LOG_FILE" | sed 's/.*fixture_scan_health_badge=//')"
if [[ -z "$FIXTURE_SCAN_HEALTH_BADGE" ]]; then
  echo "E2E failed: fixture scan health badge missing from smoke output" >&2
  exit 1
fi

if ! grep -q "fixture_scan_health_badge_matches_export=true" "$LOG_FILE"; then
  echo "E2E failed: fixture scan health badge does not match export root_health_badge" >&2
  exit 1
fi

if [[ "$FIXTURE_SCAN_HEALTH_BADGE" != *"song warning"* ]]; then
  echo "E2E failed: fixture scan health badge missing song warning signal" >&2
  exit 1
fi

if [[ "$FIXTURE_SCAN_HEALTH_BADGE" != *"skipped at roots"* ]]; then
  echo "E2E failed: fixture scan health badge missing skipped-at-roots signal" >&2
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

if ! grep -q "diagnostics_export_summary_truncation_match=true" "$LOG_FILE"; then
  echo "E2E failed: summary truncation diagnostics export missing active match marker" >&2
  exit 1
fi

SUMMARY_TRUNCATION_EXPORT_PATH="$(grep -m1 'diagnostics_export_summary_truncation_path=' "$LOG_FILE" | sed 's/.*diagnostics_export_summary_truncation_path=//')"
if [[ -z "$SUMMARY_TRUNCATION_EXPORT_PATH" || ! -f "$SUMMARY_TRUNCATION_EXPORT_PATH" ]]; then
  echo "E2E failed: summary truncation diagnostics export path missing from smoke output" >&2
  exit 1
fi

if ! grep -q "summary_line=.*Scanned 8 songs" "$SUMMARY_TRUNCATION_EXPORT_PATH"; then
  echo "E2E failed: summary truncation export missing eight-song scan count" >&2
  exit 1
fi

if ! grep -q "summary_line=.*and 3 more" "$SUMMARY_TRUNCATION_EXPORT_PATH"; then
  echo "E2E failed: summary truncation export missing truncated title suffix" >&2
  exit 1
fi

if ! grep -q "summary_line_song_warning_titles_truncated=true" "$SUMMARY_TRUNCATION_EXPORT_PATH"; then
  echo "E2E failed: summary truncation export missing truncated=true metadata" >&2
  exit 1
fi

if ! grep -q "summary_line_song_warning_titles_cap=5" "$SUMMARY_TRUNCATION_EXPORT_PATH"; then
  echo "E2E failed: summary truncation export missing cap metadata" >&2
  exit 1
fi

if ! grep -q "summary_line_song_warning_titles_omitted=3" "$SUMMARY_TRUNCATION_EXPORT_PATH"; then
  echo "E2E failed: summary truncation export missing omitted count metadata" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_summary_truncation_footnote_match=true" "$LOG_FILE"; then
  echo "E2E failed: summary truncation panel footnote missing active match marker" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_summary_truncation_footnote=Support summary shows 5 warning song titles; 3 more listed below." "$LOG_FILE"; then
  echo "E2E failed: summary truncation panel footnote missing expected text" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_support_summary=roots:" "$LOG_FILE"; then
  echo "E2E failed: diagnostics panel support summary missing roots prefix" >&2
  exit 1
fi

if ! grep -q "diagnostics_panel_support_summary=.*Scanned 7 songs" "$LOG_FILE"; then
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

if ! grep -q "summary_line=.*Scanned 7 songs" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line song count" >&2
  exit 1
fi

if ! grep -q "summary_line=.*1 song(s) with 1 warning(s)" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line warning count" >&2
  exit 1
fi

if ! grep -q "summary_line=.*Broken Folder Example" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line song warning titles" >&2
  exit 1
fi

if ! grep -q "summary_line=.*2 skipped at roots" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: exported diagnostics missing summary_line skipped count" >&2
  exit 1
fi

if ! grep -q "root_health_badge=${FIXTURE_SCAN_HEALTH_BADGE}" "$SEARCH_EXPORT_PATH"; then
  echo "E2E failed: fixture search export root_health_badge does not match panel badge" >&2
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
