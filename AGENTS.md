# Niko Music Hub — Agent Rules

## Mission

Build **Niko Music Hub**: one native macOS SwiftUI app combining the tested OutsideCubaseHub tools with a new Cubase archive browser.

Use the existing Swift app as the seed. Do not start blank. Do not embed Electron/React/TypeScript/Python runtime code into the product. Port behavior into Swift modules.

## Product boundaries

- Native macOS app, Swift 6.x, SwiftUI + AppKit interop where useful.
- Local-first and read-only toward real music archives by default.
- Never rename, move, delete, or rewrite real Cubase/music files.
- Fixture-first tests are mandatory.
- User-style E2E is mandatory before calling v0.1 done.
- GitHub Actions are not required; local gates are the truth because billing is annoying.

## Architecture target

- `NikoMusicCore`: pure Swift domain/scanning/search/opening safety. No SwiftUI, no AppKit UI.
- `AppCore`: shared tool registry, settings, jobs, output inbox, diagnostics.
- `FeatureArchiveBrowser`: SwiftUI feature registered through the same `ToolFeature` boundary as the existing tools.
- Existing outside-Cubase features stay modular: BPM tapper, audio converter, audio recorder, downloader, output inbox.
- App target becomes `NikoMusicHub` and app name becomes `Niko Music Hub`.

## Source/reference inputs

- Product scope: `docs/product-scope.md`
- Architecture: `docs/architecture.md`
- Seed app source: current repo, copied from `/Users/example/Documents/OutSideCubaseHub`
- Cubase reference docs: `docs/reference/cubase-file-orga/`
- SwiftUI style reference: `/Users/example/src/automation-health`

## Hub polish autonomous run

If the user says **hub-polish-waves**, **run hub-polish-waves**, or **Run hub-polish-waves until complete**:

1. Read **`.ai/tasks/hub-polish-waves.json`** (authoritative wave list, acceptance, gates).
2. Read **`.ai/HANDOFF-hub-polish.md`** (last commit, next wave, blockers only).
3. Execute the **first wave with `"status": "pending"`** in order A→G. Do **not** reload the full original 10-item feature list from old chat context.
4. After the wave: run `./script/ci.sh`; mark the wave `done` + `commit` in the JSON; overwrite the handoff file; commit (push only if asked).
5. Prefer **one wave per session** (max two if small). Then stop and tell the user to send the **same kickoff phrase** again in a new chat — do not ask them to say “next”.

Waves A–C are already **done**; start at **D** unless the manifest says otherwise.

## Isolation

Do not touch:

- `/Users/example/locus`
- `/Users/example/.hermes/worktrees/locus-*`
- `/Users/example/.hermes/workers/locus-*`

Do not set or depend on `LOCUS_*` environment variables.

MacBook is read-only/reference unless a task explicitly says copy source/reference files. Do not modify MacBook projects in place.

## Local gates

Run:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

`./script/ci.sh` skips host-only CoreAudio recording tests that require a usable system-audio capture device. Those tests are still part of the source suite; they are just not a reliable always-on-Mac gate.

## Ultimate De-Slop

Vendored from [Niko96-dotcom/ultimate-de-slop](https://github.com/Niko96-dotcom/ultimate-de-slop) into this repo:

- Skill: `.cursor/skills/ultimate-de-slop/`
- Slash command: `.cursor/commands/ultimate-de-slop.md`
- Runtime state (gitignored): `.deslop/`

Kickoff phrases: **Ultimate De Slop**, **de-slop**, `/ultimate-de-slop`, or a bounded repo-wide cleanup/improvement loop.

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

### Cursor Cloud (parent-agent mode)

Stock cloud VMs do **not** ship `cursor-agent` / `codex` / `claude` / etc. Nested `deslop-loop.sh` agent stages will fail doctor/`127` here.

In cloud, the **current** agent is the parent and must play reviewer → arbiter → fixer → verifier itself while still using the deterministic harness for state:

1. Read `.cursor/skills/ultimate-de-slop/SKILL.md` and follow its safety defaults (one finding at a time, no P3 fuel, no broad rewrites).
2. Run `deslop-init.sh`, then use `.deslop/index.md` / `.deslop/inventory.json` to partition work.
3. Produce high-confidence P0/P1 findings with concrete evidence; persist via the harness scripts when possible, otherwise keep findings in `.deslop/findings.jsonl` shape from `references/finding-schema.md`.
4. Fix exactly one accepted finding, run repo gates (`./script/ci.sh`; `./script/e2e_user_smoke.sh` if UI changed), then verify against the original finding.
5. Do not load `.deslop/runs/` into chat unless debugging. Prefer `deslop-status.py` / `deslop-next.py`.
6. Stop on the same stop policy as the skill (`no_eligible_findings`, max iterations, `.deslop/stop`, finalize halt).

Do **not** confuse this with the tiny Cursor plugin skill named `deslop` (branch-diff slop cleanup). Ultimate De-Slop is the bounded whole-repo control plane.

Refresh the vendored skill from upstream when needed:

```bash
git clone --depth 1 https://github.com/Niko96-dotcom/ultimate-de-slop.git /tmp/ultimate-de-slop
/tmp/ultimate-de-slop/scripts/install/install-cursor.sh --scope local --project-dir "$(pwd)"
# then re-trim non-operational docs/CI if desired and commit
```

## Git rules

- Keep commits coherent.
- Commit only green local states during execution.
- Do not push unless the prompt or user explicitly asks for push.
- Do not commit `.ai/runs/`, `.deslop/`, build output, DerivedData, `.DS_Store`, or personal scan logs.
