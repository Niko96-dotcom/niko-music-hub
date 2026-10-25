# Ultimate De-Slop

A bounded whole-repo code-quality loop for agents. Moved here from `AGENTS.md` on 2026-10-25; the rules
are unchanged.

Vendored locally from [Niko96-dotcom/ultimate-de-slop](https://github.com/Niko96-dotcom/ultimate-de-slop) (the `.cursor/` tree is gitignored; a fresh clone re-vendors it with the refresh command below):

- Skill: `.cursor/skills/ultimate-de-slop/`
- Slash command: `.cursor/commands/ultimate-de-slop.md`
- Runtime state (gitignored): `.deslop/`

Use the vendored workflow when the user explicitly requests **Ultimate De Slop**, **de-slop**,
`/ultimate-de-slop`, or that bounded iterative workflow. Ordinary reviews, audits and scoped
cleanup do not automatically activate the harness. Follow explicit review-only or direct-work requests.

```bash
SKILL_DIR=".cursor/skills/ultimate-de-slop"
"$SKILL_DIR/scripts/deslop-init.sh"
"$SKILL_DIR/scripts/deslop-doctor.py"
"$SKILL_DIR/scripts/deslop-status.py"
```

## Desktop / Mac (nested loop)

When `cursor-agent` (or another supported harness CLI) is on `PATH`:

```bash
export DESLOP_HARNESS=cursor   # auto-detected from the install marker
"$SKILL_DIR/scripts/deslop-loop.sh" --max-iterations 5 --priority P0,P1
"$SKILL_DIR/scripts/deslop-status.py"
# later:
"$SKILL_DIR/scripts/deslop-continue.sh"
```

Review-only: `"$SKILL_DIR/scripts/deslop-review.sh"`.

## Cloud (parent-agent mode)

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
