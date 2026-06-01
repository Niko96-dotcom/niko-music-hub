# User E2E

The user-style smoke test exercises the app through the same path a real user takes, while staying fixture-only and read-only.

## Automated Smoke

```bash
./script/e2e_user_smoke.sh
```

The script:

1. Regenerates the public fixture archives.
2. Builds `dist/NikoMusicHub.app`.
3. Runs the app binary with `NIKO_MUSIC_HUB_E2E_SMOKE=1`.
4. Scans the fixture archive root.
5. Searches for `neon hk`.
6. Selects the matching song.
7. Verifies preview ranking and search explainability.
8. Opens the latest CPR in dry-run mode.
9. Proves the fixture archive tree is unchanged.
10. Launches the real app bundle through `./script/build_and_run.sh --verify`.
11. Checks that the public first-run UI is clean and does not expose fixture/temp paths or internal diagnostics.

## Environment Variables

| Variable | Purpose |
| --- | --- |
| `NIKO_MUSIC_HUB_E2E_SMOKE=1` | Run the archive smoke path and exit. |
| `NIKO_MUSIC_HUB_FIXTURE_ROOT` | Override the fixture archive root. |
| `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` | Log the latest CPR path instead of opening Cubase. |

## Manual Real-Archive Smoke

Use a local Cubase/archive folder you control:

```bash
swift run NikoMusicCoreSelfTest --real-root "<YOUR_ARCHIVE_ROOT>" --read-only
```

Expected result: song, CPR, preview, skipped-entry, and warning counts only. The read-only policy must deny writes under the scanned root.

## Recorder Hardware Check

CoreAudio recorder tests are included in source, but the default CI script skips host-only tests that require a working system-audio capture device and granted macOS privacy permission. To validate recording manually:

1. Run `./script/build_and_run.sh --verify`.
2. Open Recorder.
3. Grant macOS audio capture permission if prompted.
4. Record audible system audio.
5. Stop recording.
6. Verify the output WAV appears in the selected output folder and Output Inbox.

## Release Gates

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
./script/build_and_run.sh --verify
```
