# AI Acceptance Testing (Release UAT)

Canonical procedure for evidence-backed AI computer-use acceptance of a
release candidate. The AI executor may execute and approve all ten required checks by directly
driving the signed release app plus deterministic
filesystem/hash/audio/provider verification.

## Contract invariants (unchanged)

- Schema stays `schema_version: 1` with exactly the ten required checks
  from `script/lib/release_gates.sh` (`clean_install`,
  `upgrade_preserves_settings`, `uninstall`, `launch_at_login`,
  `privacy_permissions`, `recorder_real_audio`, `downloader_live`,
  `archive_read_only`, `output_handoffs`, `e2e_user_smoke`). No new schema
  is introduced.
- Required gates (exact 12, 4 emergency-overridable), pending/failed
  fail-closed semantics, and the frozen exact-commit/build/signing/hash
  rules are unchanged. `pending`, `failed`, or any non-`passed` value
  rejects in both the standalone and final approval validators.
- `approved_by` truthfully identifies the AI agent/session (for example
  `ai-acceptance <agent> <session>`). It never impersonates a human and
  never carries a placeholder (`TODO*`, `REPLACE_WITH_*`, blank).
- The existing validator already accepts such a non-placeholder AI actor;
  this procedure adds no leniency and weakens nothing.
- All checks need durable observation/artifact evidence for the exact
  final SHA. Policy edits require a new candidate before final acceptance:
  this document defines the procedure only; the actual acceptance record
  is left to the coordinator after live tests on the exact final commit.

## Test target

Test the exact commit as the build shape that ships, and record it under
`tested_build`:

```bash
NMH_BUILD_CONFIGURATION=release \
NMH_SIGNING_IDENTITY="$NMH_DEVELOPER_ID_APPLICATION" \
./script/install-local.sh
```

- `build_configuration` must be `release`, `signing_identity` the exact
  intended `Developer ID Application:` identity, `hardened_runtime` boolean
  `true`, and `build_id` exactly `VERSION+short12(commit)`.
- Ad-hoc/debug builds have a per-build TCC identity and no hardened
  runtime; their privacy, recorder, and login-item results do not transfer
  and the validator rejects them.
- UAT bytes are frozen to `frozen-uat.json` BEFORE validation; the frozen
  hash is re-checked after validation and at approval. Never reuse test or
  historical UAT for a real release.

## Evidence standard

- Every `passed` check cites durable evidence: screenshot and/or
  Accessibility (AX) observation of the running signed app plus file-level
  artifacts (hashes, manifests, logs) bound to the exact commit/build.
- Immutable intent and root-change coverage comes from deterministic tests
  supporting the UI; live computer-use observations confirm the shipped
  app actually behaves that way. Neither layer alone suffices.
- Never fabricate a passed result. A check that cannot be observed on the
  exact candidate stays non-`passed` with its limitation recorded precisely.
- Synthetic fixtures only; production music data and real Cubase archives
  stay untouched (read-only toward real archives by default; destructive
  cases run only on fixtures).

## Safety and capability boundaries

- No forcing logout, reboot, power-cut, TCC reset, or real audio-routing
  changes. Never describe a process relaunch as a reboot or a power-cut test.
- Existing machine permissions may be observed and exercised as-is with the
  limitation recorded; permission prompts follow the host permission
  policy.
- Login-item registration is not a real login-session launch: verify
  registration state deterministically, and where a true fresh-login launch
  is not attainable in-session, record the capability limit as blocked with
  precise evidence rather than working around it.
- The real-audio check requires actual audio capture/output inspection on
  the candidate (a genuine recording path exercised and its output
  inspected), never a fake or copied-in file standing in for a recording.
- The owner's pre-existing push/install/publication authorization stands
  and this owner-authorized AI acceptance supersedes the human-only
  condition; do not require another ordinary publication approval for this
  policy transition. Live install/publication steps still execute under
  that authorization with synthetic fixtures only.

## Per-check procedure

1. `clean_install` — Install the candidate DMG/app copy into an isolated
   location, launch, and confirm first-run state (no inherited state from
   other installs). Evidence: install log, bundle/build/commit/hash
   verification, first-run screenshot/AX.
2. `upgrade_preserves_settings` — Seed a prior-version settings domain on a
   fixture suite, install the candidate over it, and confirm settings and
   library state survive. Evidence: before/after settings dumps (fixture
   suite only), screenshots.
3. `uninstall` — Remove the candidate per the documented uninstall path and
   confirm the app bundle and its throwaway fixture suites are gone while
   the real user domain is never touched. Evidence: file-existence checks
   before/after, log.
4. `launch_at_login` — Verify login-item registration state for the
   candidate build. Mark this check `passed` only when a true fresh
   login-session launch of the exact candidate is observed. Registration
   and an in-session process relaunch are insufficient. If the host cannot
   provide that observation, leave the check non-`passed` and record the
   capability limit precisely; never force logout or reboot to obtain it.
5. `privacy_permissions` — Exercise the candidate's permission surfaces
   (microphone/audio-input, folders, accessibility where applicable) as the
   host currently grants them. Record granted/denied/limited per prompt
   with screenshots; follow host permission policy and never reset TCC.
6. `recorder_real_audio` — On a machine with a usable capture setup, drive
   a real recording in the candidate and inspect genuine captured output
   (duration, non-silent content, output file hash). A stub file is never
   evidence. If no capture device exists, record the block precisely and
   leave the check non-`passed`.
7. `downloader_live` — Run a real provider download through the candidate
   against live test media on synthetic destinations, then verify output
   bytes and handoff. Evidence: provider response/log, output hash, player
   or checksum inspection.
8. `archive_read_only` — Browse a synthetic archive fixture in the
   candidate and prove no rename/move/delete/rewrite of source material;
   verify read-only behavior via filesystem snapshots (hashes before/after)
   and AX-visible read-only affordances.
9. `output_handoffs` — Complete converter/recorder/downloader output handoffs
   on fixture material: verify produced files are registered in the Output Inbox,
   reveal the correct file, and exercise drag-out to a disposable destination.
   Also verify manifest and content hashes BEFORE any Vault source removal,
   confirm Keep-Local/copy-only behavior (originals intact), exercise Undo
   of a queued Done item, plus cancellation/retry paths and
   relaunch/restore of queued work. Evidence: manifests, hash comparisons,
   queue/progress screenshots and AX, relaunch state screenshots.
10. `e2e_user_smoke` — Run the user-style end-to-end pass on the signed
    candidate (`NMH_STRICT_UI_E2E=1` semantics for public mode). The core
    interaction is a real pointer drag of a synthetic song card onto Done —
    not an alternate menu action or keyboard shortcut standing in for the
    drag — followed by its confirmation, queue/progress observation,
    verified manifest/content hashes before source removal, Keep
    Local/copy-only confirmation, Undo of the queued Done, a
    cancellation/retry exercise, and a relaunch/restore check.
    Evidence: drag-path screenshots/AX frames, confirmation and progress
    captures, hash logs, undo/cancel/retry captures, relaunch capture.

## Recording the result

- Fill a copy of `docs/release-uat-evidence.template.json` kept outside
  the repository. `approved_by` is the truthful AI executor identifier
  (`TODO_TEST_EXECUTOR_REQUIRED` is only the template sentinel and must be
  replaced); `approved_at_utc` and `machine` are real values.
- Set a check to `passed` only with the durable evidence above. Anything
  blocked or unobserved stays non-`passed` and fails closed.
- Hand the evidence bundle (JSON + screenshots/AX dumps + hash logs +
  exact commit/build/identity bindings) to the coordinator, who produces
  the final acceptance record after live tests on the exact final SHA.

## Gates the coordinator runs

```bash
python3 Tests/test_release_provenance.py
bash Tests/test_release_scripts.sh
# full gates later: ./script/ci.sh, ./script/e2e_user_smoke.sh, release-all.sh paths
```
