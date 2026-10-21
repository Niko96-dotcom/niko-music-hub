# AI Acceptance Testing (Release UAT)

The owner-approved personal-project release scope is six functional smoke
scenarios on the current macOS account. The owner selected this scope on
2026-10-21 to avoid requiring a separate account or a fresh login for every
release. AI computer-use may execute and approve the smoke, with truthful
executor identity and durable evidence for every required pass.

## Contract

`script/lib/release_gates.sh` is the single source of truth. UAT JSON keeps
`schema_version: 1` and has exactly these six required `checks`, all `passed`:

1. `exact_candidate_launch_and_current_settings`
2. `synthetic_wav_conversion`
3. `genuine_system_audio_capture`
4. `live_provider_download`
5. `synthetic_archive_read_only_browse`
6. `output_inbox_and_exact_reveal`

Any pending, failed, waived, missing or unknown required check rejects the
release. Historical ten-check records cannot approve this scope by dropping
unperformed checks: issue a new record only after observing the six scenarios
on the exact final candidate.

The record must separately disclose exactly these `excluded_checks`:

| Excluded work | Recorded result |
| --- | --- |
| `separate_account_clean_install` | `waived` |
| `disposable_uninstall` | `waived` |
| `fresh_login_launch_at_login` | `waived` |
| `deep_pointer_done_vault_queue` | `not_run` |

These disclosures are not successful tests. The last exclusion covers pointer
drag-out/Done, Vault source/destination manifest and Keep Local exercises,
queued Done Undo, cancellation/retry and queued-work relaunch/restore. They
remain useful optional investigations, with their own evidence, but are not
prerequisites for this release smoke. Existing permission grants may be used;
new/denied permission-prompt paths are not thereby claimed tested.

The twelve automated/artifact release gates and four narrowly allowed
emergency exceptions are unchanged. Required source CI, strict development
E2E, release-configuration and Thread Sanitizer checks remain. This UAT scope
does not waive identity, signing, notarization, hash, provenance, update-feed
or real-data safeguards.

## Exact candidate

Test a release-configuration, Developer ID, hardened-runtime app built from
the exact final commit. Record its canonical `VERSION+short12(commit)` build
ID and intended signing identity under `tested_build`; correlate the running
PID, bundle metadata and executable hash with the prepared candidate.

Ad-hoc/debug fixture copies cannot approve the signed candidate's behavior.
A policy/source change requires a new commit, new candidate and fresh smoke
for that candidate. Never rewrite old observations to claim a later build
was tested. `approved_by` names the actual AI agent/session, never an
impersonated human. `approved_at_utc` is the actual approval time.

The pipeline freezes UAT bytes before validation and binds the same bytes to
final approval. Exact commit/build/signing checks and frozen hash checks are
unchanged. Copy `docs/release-uat-evidence.template.json` into the private
project evidence directory and approve it only after all six scenarios pass.

## Current-account safety

- Inspect ongoing work before quitting or replacing an app. Keep the prior
  installation available. Use a separate candidate location where useful.
- Capture relevant settings, library roots, output path, existing Inbox items,
  song metadata and Vault state before the test. Verify preservation afterward;
  record ordinary UI/update preference writes and owned test outputs explicitly.
- Temporarily choose a project-local synthetic output folder through the UI;
  restore that choice through the UI afterward. Never overwrite the real
  preferences domain with a snapshot to hide writes. If a minimal settings
  correction is needed, preserve its exact before/after state and explain it.
  Investigate unexpected changes and verify preservation before approval.
- All write/destructive/archive/restore exercises use synthetic fixtures.
  Never move, remove or rewrite real music. Browse real archives read-only.
- No new account, forced logout/reboot, TCC reset, password/security changes
  or real audio-routing changes are needed for this smoke. Permission prompts
  still follow the host's permission policy; unavailable capture is a failed
  or pending required check, not permission to use fake audio.

## Six observed scenarios

1. **Launch and current settings:** launch the exact signed candidate; observe
   its build and functioning main window. Compare current-account settings and
   root identities with the prior state, then verify them again after the full
   smoke. Record any discrepancy, cause if known, correction and final readback.
   Preserve checked metadata/Vault tables and existing Inbox entries.
2. **Conversion:** convert synthetic non-silent audio through the app. Inspect
   the produced file's format, duration, non-silent content and SHA-256. Verify
   the synthetic source stayed unchanged and output went to the chosen folder.
3. **Recording:** drive a genuine system-audio recording in the candidate.
   Play a synthetic signal using the existing audio setup and inspect the actual
   captured output (duration, signal/non-silence, format and hash). A copied or
   stub file never satisfies this check. Do not change audio routing or reset TCC.
4. **Download:** complete a live provider download of short test media through
   the candidate. Inspect output bytes, duration/audio and hash. Preserve real
   provider failures as failures for those attempts; a successful alternate test
   URL needs its own observed output and is not a relabelled failed attempt.
5. **Archive read-only:** browse a synthetic archive and its project versions
   in the app. Compare source membership, modes and hashes before/after. Capture
   the actual visible results; typing a query or scanning alone is insufficient.
6. **Inbox/reveal:** observe the converter, recorder and downloader outputs
   registered and available in the Output Inbox. Reveal a produced file and
   verify Finder selects that exact path. Pointer drag-out is excluded rather
   than substituted with a different action.

Each required pass cites durable AX/screenshot observations plus the relevant
filesystem, hash, audio or provider artifacts. Neither source tests alone nor
an action-call success is GUI acceptance. Keep evidence private in the project;
never commit personal settings, real archives, credentials or raw local logs.

## Approval and publication

Set `status: approved` only when all six required checks genuinely pass and
excluded work is disclosed with the exact waived/not_run states. A missing
prerequisite stays pending/failed. Run both the standalone UAT validator and
the normal release rehearsal/publication workflow without bypassing gates.
Public artifact verification, hosted-byte validation and update delivery remain
part of `docs/release.md` and `docs/release-validation.md`.
