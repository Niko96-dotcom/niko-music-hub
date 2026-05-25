# Phase 3: Cubase-Ready WAV Conversion - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md - this log preserves the alternatives considered.

**Date:** 2026-05-05T08:46:12+02:00
**Phase:** 03-cubase-ready-wav-conversion
**Areas discussed:** Project WAV preset, Batch conversion flow, Output handoff

---

## Project WAV Preset

### Default Conversion Target

| Option | Description | Selected |
|--------|-------------|----------|
| 48 kHz / 24-bit / stereo | Existing app default and common Cubase-ready format. | |
| 44.1 kHz / 24-bit / stereo | User's usual target for Cubase projects. | Yes |
| Ask each time | Safer for mixed projects, but slower during production. | |
| Other | User could provide an exact custom preset. | |

**User's choice:** 44.1 kHz / 24-bit / stereo.
**Notes:** User also requested changing the existing app default. `AudioPreset.cubaseDefault` and the settings test assertion were updated during discussion.

### Mono Source Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Keep mono when source is mono | Avoids duplicating mono samples while stereo sources stay stereo. | Yes |
| Always output stereo | Every converted file matches the preset channel layout exactly. | |
| Ask per batch | Flexible but adds friction before converting. | |

**User's choice:** Keep mono when source is mono.
**Notes:** Stereo sources should remain stereo.

### Preset Matching

| Option | Description | Selected |
|--------|-------------|----------|
| Always match preset | Every output uses the selected sample rate and bit depth. | Yes |
| Preserve source when possible | Fewer transformations, but less consistent Cubase output. | |
| Warn before changing | Explicit, but adds friction before each batch. | |

**User's choice:** Always match preset.
**Notes:** The selected preset governs sample rate and bit depth.

### Verification Failure

| Option | Description | Selected |
|--------|-------------|----------|
| Mark failed and keep the source untouched | Safest; no questionable output appears as ready for Cubase. | Yes |
| Keep the output but mark it failed | Useful for inspection, but risks accidental handoff. | |
| Retry once with FFmpeg fallback | Helpful in some mismatch cases, but depends on fallback availability. | |

**User's choice:** Mark failed and keep the source untouched.
**Notes:** Unverified files must not be treated as usable outputs.

---

## Batch Conversion Flow

### Accepted Source Formats

| Option | Description | Selected |
|--------|-------------|----------|
| M4A, MP3, WAV, AIFF, FLAC | Practical producer set; native where possible and FFmpeg fallback for broader support. | Yes |
| M4A, MP3, WAV, AIFF only | Simpler and likely enough for day one. | |
| Anything FFmpeg can read | Widest support, but harder to make clean and predictable. | |
| M4A only first | Tightest implementation, but less useful as a batch converter. | |

**User's choice:** M4A, MP3, WAV, AIFF, and FLAC.
**Notes:** This is the v1 common-audio set.

### Dropped Folder Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Scan top-level audio files only | Predictable and avoids surprise recursive batch jobs. | Yes |
| Recursively scan subfolders | Useful for sample packs, but can create huge accidental jobs. | |
| Reject folders | Simplest, but less convenient. | |

**User's choice:** Scan top-level audio files only.
**Notes:** Recursive folder scanning is out of scope for Phase 3.

### Native And FFmpeg Fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Native first, FFmpeg fallback on unsupported/failure | Keeps normal paths native while handling broader formats. | Yes |
| FFmpeg for every file | Consistent and broad, but depends on helper availability for all conversion. | |
| Native only unless user manually enables FFmpeg | Fewer external-tool surprises, but less recoverable. | |

**User's choice:** Native first, FFmpeg fallback on unsupported/failure.
**Notes:** FFmpeg remains behind an adapter boundary.

### Missing FFmpeg

| Option | Description | Selected |
|--------|-------------|----------|
| Fail only that file with helper guidance | Batch continues, and the user sees FFmpeg is needed for that file. | Yes |
| Stop the whole batch | Makes missing helper obvious, but blocks native-convertible files. | |
| Ask before continuing | Explicit, but interrupts long batches. | |

**User's choice:** Fail only that file with helper guidance.
**Notes:** Native-convertible files should continue.

### Cancellation

| Option | Description | Selected |
|--------|-------------|----------|
| Cancel remaining files, finish current file safely | Avoids half-written output while stopping predictably. | Yes |
| Stop immediately | Faster, but may leave temporary or partial files to clean up. | |
| Cancel only selected files | Powerful, but more UI surface than Phase 3 needs. | |

**User's choice:** Cancel remaining files, finish current file safely.
**Notes:** Remaining queued files should not run.

---

## Output Handoff

### Output Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Source name + preset suffix | Example: `Kick Loop - 44100Hz 24bit.wav`; easy to trust before dragging. | Yes |
| Source name only | Cleanest names, but conflicts and specs are less visible. | |
| Timestamped session names | Avoids conflicts, but files are harder to recognize. | |
| Ask per batch | Flexible, but slows the workflow. | |

**User's choice:** Source name + preset suffix.
**Notes:** Naming should make Cubase-readiness visible.

### Filename Conflicts

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-append a counter | Fastest and avoids overwriting. | Yes |
| Overwrite after confirmation | Keeps one canonical file, but adds risk and friction. | |
| Fail that file | Safest for existing files, but annoying during batch work. | |

**User's choice:** Auto-append a counter.
**Notes:** Example counter behavior: `Kick Loop - 44100Hz 24bit 2.wav`.

### Output Inbox Metadata

| Option | Description | Selected |
|--------|-------------|----------|
| Source file + verified specs + converter used | Enough to trust the result and debug native vs FFmpeg behavior. | Yes |
| Verified specs only | Simpler, but less traceable. | |
| Full technical log | Very debuggable, but too noisy for the inbox. | |

**User's choice:** Source file + verified specs + converter used.
**Notes:** Full logs can remain job logs rather than inbox metadata.

### Drag-Out Surface

| Option | Description | Selected |
|--------|-------------|----------|
| Both converter results and output inbox | Fast immediately after conversion and reusable later from the shared inbox. | Yes |
| Output inbox only | Simpler and consistent, but adds an extra step after conversion. | |
| Converter results only | Good for Phase 3, but weakens the shared inbox pattern. | |

**User's choice:** Both converter results and output inbox.
**Notes:** Supports immediate Cubase handoff and later handoff from saved outputs.

---

## the agent's Discretion

- Exact converter UI layout.
- Exact metadata key names.
- Exact temporary-file cleanup strategy.
- Exact native conversion coverage and fallback detection details.
- Exact per-file progress granularity.

## Deferred Ideas

None - discussion stayed within Phase 3 scope.
