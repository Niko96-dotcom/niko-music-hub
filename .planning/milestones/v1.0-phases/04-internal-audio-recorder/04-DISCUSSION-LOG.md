# Phase 4: Internal Audio Recorder - Discussion Log

**Discussed:** 2026-05-11
**Phase:** 04-internal-audio-recorder

## Areas Discussed

### 1. Start Trigger
**Question:** Recording start — button only, or also keyboard shortcut?
**Options presented:** Button only | Button + Spacebar shortcut | You decide
**Selected:** Button + Spacebar shortcut
**Rationale:** Convenient for quick start; mirrors BPM tapper spacebar convention when tool is active.

### 2. Live Feedback During Recording
**Question:** What to show during active recording?
**Options presented:** Elapsed time + stop button only | Live audio meters + elapsed time + stop button | You decide
**Selected:** Live audio meters + elapsed time + stop button
**Rationale:** Visual confirmation that audio is being captured is essential for a recording tool — lets user verify signal is present.

### 3. Output File Naming
**Question:** How should output files be named?
**Options presented:** Auto timestamp (`Recording YYYY-MM-DD HH-mm-ss.wav`) | User-provided name before recording | Auto timestamp with optional override | You decide
**Selected:** Auto timestamp with optional override
**Rationale:** Auto timestamp keeps files organized by session; override option handles cases where user wants a meaningful name.

### 4. Max Recording Duration
**Question:** Should there be a max recording duration?
**Options presented:** Unlimited (user stops when done) | Configurable max with sensible default | You decide
**Selected:** Configurable max with sensible default (30 min)
**Rationale:** Prevents accidental multi-hour recordings that fill the disk; user can adjust or disable in preferences.

---

## Deferred Ideas

None — all discussion stayed within Phase 4 scope.

---

*Phase: 04-internal-audio-recorder*
*Discussion: 2026-05-11*