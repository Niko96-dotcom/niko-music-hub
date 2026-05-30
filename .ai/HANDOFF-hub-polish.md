# hub-polish handoff

**Manifest:** `.ai/tasks/hub-polish-waves.json`  
**Kickoff:** `Run hub-polish-waves until complete`

## Current

| Field | Value |
|-------|--------|
| Last completed wave | D (commit pending this run) |
| Last commit | — |
| Next wave | **E** — WAV converter FFmpeg path UX |
| Blocked | — |

## Resume instructions (agents)

1. Read `hub-polish-waves.json` — first wave with `"status": "pending"`.
2. Implement only that wave; run `./script/ci.sh`.
3. Set wave `status` to `done` and set `commit` SHA in the JSON.
4. Replace this file with updated table (keep under ~25 lines).
5. Commit. Stop if two waves done this session or context is high; user re-sends kickoff phrase.

## Done summary (do not re-implement)

- **A** `d1c61c2` — preview maturity ranker, titles from main preview
- **B** `4129ddd` — archive root persist + dev default
- **C** `e6e9872` — downloader audio/video format menus
- **D** — median tempo estimator, tuple/jitter tests, `docs/bpm-tapper-algorithm.md`
