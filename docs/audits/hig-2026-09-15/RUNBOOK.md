# HIG overnight runbook (operational amendments)

AGENTS.md still governs safety, boundaries, and mandatory gates. Product acceptance criteria (D1–D8) are unchanged. These are limited execution amendments for the unattended overnight run.

## Verified environment

- Host: MBP-von-Niko / macOS 26.5.2 / user `niko`
- Repo checkout (original, untouched except pre-existing `.gitignore`): `/Users/niko/Documents/Niko-Music-Hub`
- Starting `main` SHA: `55e8cf8f98fe8e4a46d0ac7066c1643070a2f62c`
- Integration worktree/branch: `hig-audit-fixes` (from local main; no fetch/pull/push)
- Durable run directory (outside repo): see `RUN_ROOT` file beside this worktree's parent

## Tooling (verified CLI IDs)

| Role | CLI | Model ID | Notes |
|---|---|---|---|
| Primary coder | `agent` (`/Users/niko/.local/bin/agent`) | `cursor-grok-4.6-xhigh` | Included Cursor account; do not use Codex |
| Reviewer / fallback coder | `opencode` 1.18.31 | `opencode-go/muse-spark-1.3-contributor` | OpenCode Go subscription; try `--variant xhigh` then `high` if rejected |
| Gates | `./script/ci.sh`, `./script/e2e_user_smoke.sh` | — | Must use `NIKO_MUSIC_HUB_SETTINGS_SUITE` isolation |

Credentials stay in existing local stores (Cursor login, OpenCode auth). Never extract into prompts, logs, or launchd plists.

## Amendments

### A. Ledger path
Canonical tracked ledger: `docs/audits/hig-2026-09-15/FIX-LEDGER.md` (exactly 144 item rows). Aux summaries live outside the table. Intermediate states allowed: `pending`, `in-progress`, `implemented-awaiting-runtime`, `blocked` — none count as completed.

### B. Commit / SHA recording
A commit cannot contain its own final hash. Implementation commits include item status/evidence + unique batch id; record actual SHA in the durable journal immediately; reconcile into the ledger in later commits + a final evidence-only commit. No amend loops for self-referential hashes.

### C. Final verification seal
Commit ledger/changelog/gate summaries first; run both mandatory gates on that exact final SHA; store final-SHA attestation + full outputs in the durable run directory, linked from the ledger. Do not commit merely to insert that commit's own verification output.

### D. CODE-RED vs ENVIRONMENT-BLOCKED
Genuine failing build/test/phase gate = CODE-RED (blocks dependents). Missing human permission / GUI session / hardware = ENVIRONMENT-BLOCKED (verification pending; independent green work may continue). Never label a missing gate passed.

### E. Ordering
Follow phase order and explicit dependencies. Only ONE agent edits code at a time. Supervisor alone commits and fast-forwards `hig-audit-fixes`.

## Isolation

- Never touch real music / Active Projects / Project Vaults / live prefs.
- App launches must set `NIKO_MUSIC_HUB_SETTINGS_SUITE` (see `script/e2e_user_smoke.sh`). `$HOME` override alone is not isolation.
- Prefer `./script/ci.sh` and suite-isolated smoke; do not launch installed production app.

## Spend policy

Zero additional spend. No overages, upgrades, other accounts, paid API fallback, Codex, or Antigravity.

## Amendment (2026-09-16 14:35 CEST)
Primary coding worker switched to OpenCode `opencode-go/muse-spark-1.3-contributor` variant `xhigh` after Cursor agent usage exhausted (`ActionRequiredError`). Credentials remain in `~/.local/share/opencode/auth.json` (opencode-go). Invocation uses `opencode run --pure` + `OPENCODE_CONFIG_CONTENT` (same proven path as subscription-squad worker). Do not buy Cursor credits unless explicitly authorized.
