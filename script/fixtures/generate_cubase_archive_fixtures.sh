#!/usr/bin/env bash
# Generates deterministic Cubase archive fixtures for unit tests and E2E.
# CPR files are zero-byte placeholders (not copied from real projects).
#
# Modification times are fixed absolute values in the past, never "now": ranking tiebreak
# fixtures need paired files with identical mtimes, and git checkouts rewrite files with
# checkout-time mtimes. `--restamp` re-applies only the timestamps to an existing tree
# (non-destructive; the test helpers use it when a checkout has scrambled them).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE_ROOT="$ROOT/Fixtures/CubaseArchive"
TRUNCATION_ROOT="$ROOT/Fixtures/CubaseArchiveSummaryTruncation"
# Keep in sync with `CubaseFixtures.fixtureEpoch` in Tests/*/Fixtures.swift.
FIXTURE_EPOCH=1700000000

stamp_fixture_mtimes() {
  /usr/bin/python3 - "$FIXTURE_ROOT" "$TRUNCATION_ROOT" "$FIXTURE_EPOCH" <<'PY'
import os, sys
archive, truncation, epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
# Offsets (seconds after the epoch) that decide recency-sensitive rankings. Files listed
# together share one mtime so a later tiebreak (version, extension, duration) decides.
offsets = {
    120: ["Neon Hook/Neon Hook.cpr"],  # latest CPR beats "Neon Hook v2.cpr"
    300: ["Preview Ranking Lab/Mixdown/Lab Song v5 instr.wav"],
    350: ["Preview Ranking Lab/Mixdown/Lab Song v3 mix.wav",
          "Preview Ranking Lab/Mixdown/Lab Song v2 mix.wav"],
    400: ["Equal Score Duration Tiebreak/Mixdown/Tie Song mix long.wav",
          "Equal Score Duration Tiebreak/Mixdown/Tie Song mix short.wav"],
    500: ["Equal Score Version Tiebreak/Mixdown/Tie Song v3 mix.wav",
          "Equal Score Version Tiebreak/Mixdown/Tie Song v2 mix.wav"],
    600: ["Equal Score Extension Tiebreak/Mixdown/Tie Song mix.flac",
          "Equal Score Extension Tiebreak/Mixdown/Tie Song mix.mp3"],
    700: ["90s Rave/Mixdown/Graffiti SESSIN BOUNCE.wav"],
    750: ["Amber Moth/Mixdown/Amber Moth drums.wav"],
}
for root in (archive, truncation):
    for directory, dirs, files in os.walk(root):
        for name in files + dirs:
            os.utime(os.path.join(directory, name), (epoch, epoch))
    os.utime(root, (epoch, epoch))
for offset, paths in offsets.items():
    for relative in paths:
        os.utime(os.path.join(archive, relative), (epoch + offset, epoch + offset))
PY
}

if [[ "${1:-}" == "--restamp" ]]; then
  stamp_fixture_mtimes
  exit 0
fi

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

# Equal Score Duration Tiebreak — same ranking signals except duration (tiebreak, not score bump)
write_placeholder_cpr "$FIXTURE_ROOT/Equal Score Duration Tiebreak/Equal Score Duration Tiebreak.cpr"
write_minimal_wav "$FIXTURE_ROOT/Equal Score Duration Tiebreak/Mixdown/Tie Song mix long.wav" 210
write_minimal_wav "$FIXTURE_ROOT/Equal Score Duration Tiebreak/Mixdown/Tie Song mix short.wav" 200

# Equal Score Version Tiebreak — matched score; version is the deciding tiebreak
write_placeholder_cpr "$FIXTURE_ROOT/Equal Score Version Tiebreak/Equal Score Version Tiebreak.cpr"
write_minimal_wav "$FIXTURE_ROOT/Equal Score Version Tiebreak/Mixdown/Tie Song v3 mix.wav" 200
write_minimal_wav "$FIXTURE_ROOT/Equal Score Version Tiebreak/Mixdown/Tie Song v2 mix.wav" 200

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

# 90s Rave — maturity ladder: master beats session bounce; display title from preview
write_placeholder_cpr "$FIXTURE_ROOT/90s Rave/90s Rave.cpr"
write_minimal_wav "$FIXTURE_ROOT/90s Rave/Mixdown/Graffiti SESSIN BOUNCE.wav" 200
write_minimal_wav "$FIXTURE_ROOT/90s Rave/Mixdown/Graffiti master.wav" 200
write_minimal_wav "$FIXTURE_ROOT/90s Rave/Mixdown/Graffiti sketchyy.wav" 200

# Amber Moth — drum stem must not become main preview
write_placeholder_cpr "$FIXTURE_ROOT/Amber Moth/Amber Moth.cpr"
write_minimal_wav "$FIXTURE_ROOT/Amber Moth/Mixdown/Amber Moth drums.wav" 200
write_minimal_wav "$FIXTURE_ROOT/Amber Moth/Mixdown/Amber Moth master mix.wav" 200

# Broken folder — no CPR
mkdir -p "$FIXTURE_ROOT/Broken Folder Example"
echo "notes only" >"$FIXTURE_ROOT/Broken Folder Example/notes.txt"

# Summary-line truncation lab — eight warning-only songs (no CPR) for diagnostics E2E
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
- Do not copy real user archive binaries into this tree.
EOF

stamp_fixture_mtimes

echo "Generated fixtures under $FIXTURE_ROOT"
echo "Generated summary truncation lab under $TRUNCATION_ROOT"
