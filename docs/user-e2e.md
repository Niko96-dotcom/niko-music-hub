# User E2E — Niko Music Hub

## Fixture smoke (automated)

```bash
./script/e2e_user_smoke.sh
```

This script:

1. Regenerates `Fixtures/CubaseArchive/`
2. Builds `dist/NikoMusicHub.app`
3. Runs the app with `NIKO_MUSIC_HUB_E2E_SMOKE=1` (CLI hook — not pgrep-only)
4. Drives the same `ArchiveUserFlowSmoke` path as unit tests: fixture root → scan → fuzzy search **neon hk** → dry-run open latest CPR
5. Asserts stdout includes user-flow markers, search match explainability (`search_match_summary`), CPR path, dry-run log, read-only write-probe, and unchanged fixture tree

Environment variables:

| Variable | Purpose |
|----------|---------|
| `NIKO_MUSIC_HUB_E2E_SMOKE=1` | Run smoke and exit (no UI required) |
| `NIKO_MUSIC_HUB_FIXTURE_ROOT` | Cubase archive fixture root |
| `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` | Log CPR path without launching Cubase |

## Real archive read-only smoke (manual)

Replace `<YOUR_ARCHIVE_ROOT>` with your Cubase projects folder:

```bash
swift run NikoMusicCoreSelfTest --real-root "<YOUR_ARCHIVE_ROOT>" --read-only
```

Expect song/CPR/preview counts only. The process must not write under the scanned root (`ReadOnlyArchivePolicy` write-probe).

## Local gates

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```
