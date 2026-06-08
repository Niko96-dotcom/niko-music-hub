# Contributing

Niko Music Hub is a native macOS SwiftUI app. Keep product code in Swift and keep archive access read-only by default.

## Daily Loop

```bash
./script/dev.sh run
```

You can also double-click `Run Niko Music Hub.command` in Finder. The Codex Run action still points directly at `./script/build_and_run.sh`, the lower-level build/run entrypoint.

## Required Local Gates

Run the friendly full check before calling a change done:

```bash
./script/dev.sh check
```

That wraps the required local gates:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
./script/build_and_run.sh --verify
```

`script/ci.sh` skips host-only CoreAudio capture tests that need a usable system-audio capture device. Those tests stay in the source suite; they are just not the always-on local gate.

For setup diagnosis:

```bash
./script/dev.sh doctor
```

## Visual Proof

For app-window evidence:

```bash
./script/capture_window_proof.sh
```

Window proof and accessibility dumps use `script/ui_probe.swift` (CoreGraphics window matching plus ApplicationServices AX; no pyobjc).

Expected artifacts:

- `dist/window-visible-proof.png`
- `dist/desktop-proof.png`

## Git Hygiene

- Keep commits coherent and green.
- Do not commit `.ai/runs/`, `.build/`, `dist/`, `DerivedData/`, `.DS_Store`, `.xcresult`, or personal scan logs.
- Do not push unless the current task explicitly asks for it.
- GitHub Actions are not required; paste local gate results into PRs instead.
