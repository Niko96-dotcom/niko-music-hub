# Shared release gate and UAT contract for Niko Music Hub.
# shellcheck shell=bash
#
# Single source of truth for the exact required release gate set, the narrowly
# allowed emergency exceptions, and the exact required UAT check set. Both
# validators (script/validate-release-uat.sh, script/validate-release-approval.sh)
# source this file so the lists cannot drift, duplicate, or go incomplete in one
# place while another place enforces a weaker subset. Approvals must carry
# exactly NMH_REQUIRED_RELEASE_GATES with no duplicates, no missing entries,
# and no unknown entries; only NMH_EMERGENCY_OVERRIDABLE_GATES may use
# emergency-override. UAT evidence checks must be exactly
# NMH_REQUIRED_UAT_CHECKS, all passed.

# Exact required release gates, in pipeline order. Names must match the --gate
# names emitted by script/release-all.sh.
NMH_REQUIRED_RELEASE_GATES=(
  clean-tagged-checkout
  consolidated-mac-uat
  debug-ci
  user-e2e
  release-configuration
  thread-sanitizer
  release-identity
  release-platform-contract
  public-tree-hygiene
  sign-notarize-staple
  artifact-validation
  update-feed
)

# Narrowly allowed emergency exceptions: only the automated test gates that
# release-all.sh marks emergency-override under --emergency-skip-tests. All
# other gates (identity, hygiene, signing, artifact, feed, UAT, checkout) must
# always be passed; an override there is a disallowed override.
NMH_EMERGENCY_OVERRIDABLE_GATES=(
  debug-ci
  user-e2e
  release-configuration
  thread-sanitizer
)

# Exact required UAT checks. The evidence checks object must contain exactly
# this set, all passed.
NMH_REQUIRED_UAT_CHECKS=(
  clean_install
  upgrade_preserves_settings
  uninstall
  launch_at_login
  privacy_permissions
  recorder_real_audio
  downloader_live
  archive_read_only
  output_handoffs
  e2e_user_smoke
)

nmh_required_release_gates() {
  printf '%s\n' "${NMH_REQUIRED_RELEASE_GATES[@]}"
}

nmh_emergency_overridable_gates() {
  printf '%s\n' "${NMH_EMERGENCY_OVERRIDABLE_GATES[@]}"
}

nmh_required_uat_checks() {
  printf '%s\n' "${NMH_REQUIRED_UAT_CHECKS[@]}"
}

nmh_is_emergency_overridable_gate() {
  local gate="${1:?missing gate name}"
  local allowed
  for allowed in "${NMH_EMERGENCY_OVERRIDABLE_GATES[@]}"; do
    if [[ "$gate" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}
