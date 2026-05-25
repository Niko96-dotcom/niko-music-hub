---
status: partial
phase: 03-cubase-ready-wav-conversion
source: [03-VERIFICATION.md]
started: 2026-05-06T17:10:25Z
updated: 2026-05-06T17:10:25Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Running App Conversion Flow
expected: Launch `OutsideCubaseHub`, select `WAV Converter`, choose/drop real M4A, MP3, WAV, AIFF, and FLAC files, run a batch, trigger a missing-FFmpeg recovery row if possible, and use `Stop After Current File`. Supported files become rows, unsupported files show row errors, native-convertible files continue when FFmpeg is missing, progress and final row states match the batch, and verified outputs are created.
result: [pending]

### 2. Finder/Cubase Drag Smoke
expected: Convert a short file, then drag from a verified converter row into Finder and Cubase; also drag from the shared output inbox. The dragged payload is the verified output WAV file URL and imports/lands as a file, not source metadata or a temp path. Failed, skipped, and unverified rows are not draggable.
result: [pending]

### 3. Output Inbox Live Appearance
expected: With the inspector visible, complete a conversion and watch whether the new output appears without reopening or recreating the view. The shared output inbox shows the newly converted item with metadata, reveal, and drag affordances.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
