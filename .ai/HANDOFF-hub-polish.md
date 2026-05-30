# hub-polish handoff

**Manifest:** `.ai/tasks/hub-polish-waves.json`  
**Kickoff:** `Run hub-polish-waves until complete`

## Current

| Field | Value |
|-------|--------|
| Last completed wave | E (commit pending this run) |
| Last commit | `8ae883b` — wave D BPM tapper |
| Next wave | **F** — UI chrome (inbox + sidebars) |
| Blocked | — |

## Resume instructions (agents)

1. Read `hub-polish-waves.json` — first wave with `"status": "pending"`.
2. Implement only that wave; run `./script/ci.sh`.
3. Set wave `status` to `done` and set `commit` SHA in the JSON.
4. Replace this file (keep under ~25 lines).
5. Commit. Stop after two waves per session; user re-sends kickoff phrase.

## Done summary (do not re-implement)

- **A** `d1c61c2` — preview maturity ranker
- **B** `4129ddd` — archive root persist
- **C** `e6e9872` — downloader format menus
- **D** `8ae883b` — median BPM estimator + `docs/bpm-tapper-algorithm.md`
- **E** — `resolvedFFmpegURL` matches health strip; pipeline uses auto-detect without nag
