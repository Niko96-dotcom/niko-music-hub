#!/usr/bin/env bash
# Generates deterministic Cubase archive fixtures for unit tests and E2E.
# CPR files are zero-byte placeholders (not copied from real projects).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE_ROOT="$ROOT/Fixtures/CubaseArchive"

write_minimal_wav() {
  local path="$1"
  local seconds="${2:-0.1}"
  mkdir -p "$(dirname "$path")"
  /usr/bin/python3 - "$path" "$seconds" <<'PY'
import struct, sys, wave
path = sys.argv[1]
seconds = float(sys.argv[2])
frames = max(1, int(44100 * seconds))
with wave.open(path, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    w.writeframes(b"\x00\x00" * frames)
PY
}

write_placeholder_cpr() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  : >"$path"
}

rm -rf "$FIXTURE_ROOT"
mkdir -p "$FIXTURE_ROOT"

# Loose file at archive root — should be skipped (not scanned as a song folder)
echo "not a song folder" >"$FIXTURE_ROOT/LOOSE_FILE.txt"

# Neon Hook — full mix in Mixdown beats stem names
write_placeholder_cpr "$FIXTURE_ROOT/Neon Hook/Neon Hook v2.cpr"
write_placeholder_cpr "$FIXTURE_ROOT/Neon Hook/Neon Hook.cpr"
# Latest CPR for E2E is Neon Hook.cpr (newer mtime than v2)
/usr/bin/python3 - "$FIXTURE_ROOT/Neon Hook/Neon Hook.cpr" <<'PY'
import os, sys, time
path = sys.argv[1]
now = time.time() + 120
os.utime(path, (now, now))
PY
write_minimal_wav "$FIXTURE_ROOT/Neon Hook/Mixdown/Neon Hook v3.wav"
write_minimal_wav "$FIXTURE_ROOT/Neon Hook/Mixdown/Neon Hook instr.wav"
mkdir -p "$FIXTURE_ROOT/Neon Hook/Ideas"
touch "$FIXTURE_ROOT/Neon Hook/Ideas/Neon Hook topline.mid"

# Second Song — instr vs full mix filename competition
write_placeholder_cpr "$FIXTURE_ROOT/Second Song/Second Song.cpr"
write_minimal_wav "$FIXTURE_ROOT/Second Song/Mixdown/Second Song mixdown.wav"
write_minimal_wav "$FIXTURE_ROOT/Second Song/Mixdown/Second Song instr.wav"

# Preview Ranking Lab — version, extension, role, and duration competition
write_placeholder_cpr "$FIXTURE_ROOT/Preview Ranking Lab/Preview Ranking Lab.cpr"
write_minimal_wav "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown/Lab Song v3 mix.wav" 200
write_minimal_wav "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown/Lab Song v2 mix.wav" 200
/usr/bin/python3 - "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown" <<'PY'
import os, sys, time
mixdown = sys.argv[1]
now = time.time() + 350
for name in ("Lab Song v3 mix.wav", "Lab Song v2 mix.wav"):
    path = os.path.join(mixdown, name)
    os.utime(path, (now, now))
PY
write_minimal_wav "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown/Lab Song v5 instr.wav" 200
write_minimal_wav "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown/Lab Song mix.mp3" 200
/usr/bin/python3 - "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown/Lab Song mix.mp3" <<'PY'
import struct, sys
path = sys.argv[1]
# Minimal MP3-like placeholder bytes for ranking tests (not a real decode target).
with open(path, "wb") as f:
    f.write(b"ID3" + b"\x00" * 128)
PY
write_minimal_wav "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown/Lab Song short clip.wav" 5
/usr/bin/python3 - "$FIXTURE_ROOT/Preview Ranking Lab/Mixdown/Lab Song v5 instr.wav" <<'PY'
import os, sys, time
path = sys.argv[1]
now = time.time() + 300
os.utime(path, (now, now))
PY

# Equal Score Duration Tiebreak — same ranking signals except duration (tiebreak, not score bump)
write_placeholder_cpr "$FIXTURE_ROOT/Equal Score Duration Tiebreak/Equal Score Duration Tiebreak.cpr"
write_minimal_wav "$FIXTURE_ROOT/Equal Score Duration Tiebreak/Mixdown/Tie Song mix long.wav" 210
write_minimal_wav "$FIXTURE_ROOT/Equal Score Duration Tiebreak/Mixdown/Tie Song mix short.wav" 200
/usr/bin/python3 - "$FIXTURE_ROOT/Equal Score Duration Tiebreak/Mixdown" <<'PY'
import os, sys, time
mixdown = sys.argv[1]
now = time.time() + 400
for name in ("Tie Song mix long.wav", "Tie Song mix short.wav"):
    path = os.path.join(mixdown, name)
    os.utime(path, (now, now))
PY

# Equal Score Version Tiebreak — matched score; version is the deciding tiebreak
write_placeholder_cpr "$FIXTURE_ROOT/Equal Score Version Tiebreak/Equal Score Version Tiebreak.cpr"
write_minimal_wav "$FIXTURE_ROOT/Equal Score Version Tiebreak/Mixdown/Tie Song v3 mix.wav" 200
write_minimal_wav "$FIXTURE_ROOT/Equal Score Version Tiebreak/Mixdown/Tie Song v2 mix.wav" 200
/usr/bin/python3 - "$FIXTURE_ROOT/Equal Score Version Tiebreak/Mixdown" <<'PY'
import os, sys, time
mixdown = sys.argv[1]
now = time.time() + 500
for name in ("Tie Song v3 mix.wav", "Tie Song v2 mix.wav"):
    path = os.path.join(mixdown, name)
    os.utime(path, (now, now))
PY

# Equal Score Extension Tiebreak — matched score; extension is the deciding tiebreak
# (non-wav placeholders skip duration reader so scores stay equal)
write_placeholder_cpr "$FIXTURE_ROOT/Equal Score Extension Tiebreak/Equal Score Extension Tiebreak.cpr"
write_minimal_wav "$FIXTURE_ROOT/Equal Score Extension Tiebreak/Mixdown/Tie Song mix.flac" 200
/usr/bin/python3 - "$FIXTURE_ROOT/Equal Score Extension Tiebreak/Mixdown/Tie Song mix.mp3" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, "wb") as f:
    f.write(b"ID3" + b"\x00" * 128)
PY
/usr/bin/python3 - "$FIXTURE_ROOT/Equal Score Extension Tiebreak/Mixdown" <<'PY'
import os, sys, time
mixdown = sys.argv[1]
now = time.time() + 600
for name in ("Tie Song mix.flac", "Tie Song mix.mp3"):
    path = os.path.join(mixdown, name)
    os.utime(path, (now, now))
PY

# Broken folder — no CPR
mkdir -p "$FIXTURE_ROOT/Broken Folder Example"
echo "notes only" >"$FIXTURE_ROOT/Broken Folder Example/notes.txt"

# Summary-line truncation lab — eight warning-only songs (no CPR) for diagnostics E2E
TRUNCATION_ROOT="$ROOT/Fixtures/CubaseArchiveSummaryTruncation"
rm -rf "$TRUNCATION_ROOT"
mkdir -p "$TRUNCATION_ROOT"
for index in 01 02 03 04 05 06 07 08; do
  mkdir -p "$TRUNCATION_ROOT/Summary Warning $index"
  echo "truncation lab" >"$TRUNCATION_ROOT/Summary Warning $index/notes.txt"
done

cat >"$FIXTURE_ROOT/README.md" <<'EOF'
# Cubase archive fixtures

Generated by `script/fixtures/generate_cubase_archive_fixtures.sh`.

- `.cpr` files are **empty placeholders** (not real Cubase projects).
- `.wav` files are minimal valid mono WAV (~0.1s silence).
- Do not copy real MacBook archive binaries into this tree.
EOF

echo "Generated fixtures under $FIXTURE_ROOT"
echo "Generated summary truncation lab under $TRUNCATION_ROOT"
