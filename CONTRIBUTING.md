# Contributing

Niko Music Hub is a native macOS SwiftUI app. Keep product code in Swift and keep archive access read-only by default.

## Daily Loop

```bash
./script/build_and_run.sh
```

The same command is exposed as the Codex Run action in `.codex/environments/environment.toml`.

## Required Local Gates

Run both commands before calling a change done:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

`script/ci.sh` skips host-only CoreAudio capture tests that need a usable system-audio capture device. Those tests stay in the source suite; they are just not the always-on local gate.

## Visual Proof

For app-window evidence:

```bash
./script/capture_window_proof.sh
```

Window proof uses `script/window_verify.swift` (ApplicationServices/Quartz via Swift; no pyobjc).

Expected artifacts:

- `dist/window-visible-proof.png`
- `dist/desktop-proof.png`

## Git Hygiene

- Keep commits coherent and green.
- Do not commit `.ai/runs/`, `.build/`, `dist/`, `DerivedData/`, `.DS_Store`, `.xcresult`, or personal scan logs.
- Do not push unless the current task explicitly asks for it.
- GitHub Actions are not required; paste local gate results into PRs instead.
