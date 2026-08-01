# Niko Music Hub — Agent Rules

## Mission

**Niko Music Hub** is a shipped native macOS SwiftUI app (currently `1.4.2`, see `VERSION`) that combines
the outside-Cubase production tools with a Cubase archive browser and Project Vault.

The app is built. Work on it as a maintained product: extend and harden existing modules rather than
re-bootstrapping. Do not embed Electron/React/TypeScript/Python runtime code into the product — port
behavior into Swift modules instead.

## Product boundaries

- Native macOS app, Swift 6.x, SwiftUI + AppKit interop where useful.
- Local-first and read-only toward real music archives by default.
- Never rename, move, delete, or rewrite real Cubase/music files outside an explicit,
  user-confirmed Project Vault transfer.
- Fixture-first tests are mandatory.
- User-style E2E (`./script/e2e_user_smoke.sh`) is mandatory before any release.
- GitHub Actions are intentionally not configured; local gates are the source of truth.

## Architecture

- `NikoMusicCore`: pure Swift domain/scanning/search/opening safety. No SwiftUI, no AppKit UI.
- `AppCore`: shared tool registry, settings, jobs, output inbox, diagnostics.
- `FeatureArchiveBrowser`: SwiftUI feature registered through the same `ToolFeature` boundary as the
  other tools.
- Feature modules stay independent: `FeatureBPMTapper`, `FeatureAudioConverter`,
  `FeatureAudioRecorder`, `FeatureDownloader`, `FeatureStemSeparation`.
- App target is `NikoMusicHub`; bundle identity is fixed in `BUNDLE_ID`.

Full detail: `docs/architecture.md`. Product intent: `docs/product-scope.md`.

## Reference material

- Cubase archive/file-organization reference: `docs/reference/cubase-file-orga/`
- Stem separation contract: `docs/reference/stem-separation-contract.md`
- Architecture decisions: `docs/decisions/`
- Superseded design history (do **not** implement from it): `docs/UI-REDESIGN-PLAN.md`

## Planning system

This repo uses GSD. Live state lives in `.planning/`:

- `.planning/STATE.md` — current position and milestone status (authoritative)
- `.planning/ROADMAP.md` — milestone/phase plan
- `.planning/milestones/` — completed milestone archives (history; do not rewrite)
- `.planning/phases/` — phases belonging to the milestone currently in flight

Read `.planning/STATE.md` before assuming what is or is not done.

## Local gates

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

`./script/ci.sh` skips host-only CoreAudio recording tests that require a usable system-audio capture
device. Those tests are still part of the source suite; they are just not a reliable always-on-Mac gate.

Friendly wrappers: `./script/dev.sh run`, `./script/dev.sh doctor`, `./script/dev.sh check`.

## Release engineering

`VERSION` is the canonical release version; `BUNDLE_ID` is the permanent app identity. Release is
fail-closed and local: `script/release-all.sh`. Every public build requires a newly approved
exact-commit UAT record. See `docs/release.md` and `docs/release-validation.md`.

## Ultimate De-Slop

Vendored from [Niko96-dotcom/ultimate-de-slop](https://github.com/Niko96-dotcom/ultimate-de-slop):

- Skill: `.cursor/skills/ultimate-de-slop/`
- Slash command: `.cursor/commands/ultimate-de-slop.md`
- Runtime state (gitignored): `.deslop/`

Kickoff phrases: **Ultimate De Slop**, **de-slop**, `/ultimate-de-slop`, or a bounded repo-wide
cleanup/improvement loop.

```bash
SKILL_DIR=".cursor/skills/ultimate-de-slop"
"$SKILL_DIR/scripts/deslop-init.sh"
"$SKILL_DIR/scripts/deslop-doctor.py"
"$SKILL_DIR/scripts/deslop-status.py"
```

### Desktop / Mac (nested loop)

When `cursor-agent` (or another supported harness CLI) is on `PATH`:

```bash
export DESLOP_HARNESS=cursor   # auto-detected from the install marker
"$SKILL_DIR/scripts/deslop-loop.sh" --max-iterations 5 --priority P0,P1
"$SKILL_DIR/scripts/deslop-status.py"
# later:
"$SKILL_DIR/scripts/deslop-continue.sh"
```

Review-only: `"$SKILL_DIR/scripts/deslop-review.sh"`.

### Cloud (parent-agent mode)

Stock cloud VMs do **not** ship `cursor-agent` / `codex` / `claude`. Nested `deslop-loop.sh` agent
stages will fail doctor/`127` there. In cloud, the current agent is the parent and must play
reviewer → arbiter → fixer → verifier itself while still using the deterministic harness for state:

1. Read `.cursor/skills/ultimate-de-slop/SKILL.md` and follow its safety defaults (one finding at a
   time, no P3 fuel, no broad rewrites).
2. Run `deslop-init.sh`, then use `.deslop/index.md` / `.deslop/inventory.json` to partition work.
3. Produce high-confidence P0/P1 findings with concrete evidence; persist via the harness scripts when
   possible, otherwise keep findings in `.deslop/findings.jsonl` shape from
   `references/finding-schema.md`.
4. Fix exactly one accepted finding, run repo gates (`./script/ci.sh`; `./script/e2e_user_smoke.sh` if
   UI changed), then verify against the original finding.
5. Do not load `.deslop/runs/` into chat unless debugging. Prefer `deslop-status.py` / `deslop-next.py`.
6. Stop on the same stop policy as the skill (`no_eligible_findings`, max iterations, `.deslop/stop`,
   finalize halt).

Do **not** confuse this with the tiny Cursor plugin skill named `deslop` (branch-diff slop cleanup).
Ultimate De-Slop is the bounded whole-repo control plane.

Refresh the vendored skill from upstream when needed:

```bash
git clone --depth 1 https://github.com/Niko96-dotcom/ultimate-de-slop.git /tmp/ultimate-de-slop
/tmp/ultimate-de-slop/scripts/install/install-cursor.sh --scope local --project-dir "$(pwd)"
```

## Git rules

- Keep commits coherent.
- Commit only green local states during execution.
- Do not push unless the prompt or user explicitly asks for push.
- Do not commit `.deslop/`, build output, `DerivedData/`, `.DS_Store`, or personal scan logs.
