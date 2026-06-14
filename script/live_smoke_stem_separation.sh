#!/bin/bash
set -euo pipefail

# Live smoke test for stem separation.
# Skips gracefully if demucs-mlx is not installed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if ! command -v demucs-mlx >/dev/null 2>&1; then
    echo "SKIP: demucs-mlx not on PATH"
    exit 0
fi

INPUT_WAV="${TMP_DIR}/sine.wav"
OUTPUT_DIR="${TMP_DIR}/out"

python3 - <<PY
import wave, math, struct

sample_rate = 44100
duration = 2
freq = 440
num_frames = sample_rate * duration

with wave.open("${INPUT_WAV}", "w") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(sample_rate)
    for i in range(num_frames):
        sample = int(32767 * math.sin(2 * math.pi * freq * i / sample_rate))
        w.writeframes(struct.pack("<hh", sample, sample))
PY

echo "Input: ${INPUT_WAV}"
echo "Output: ${OUTPUT_DIR}"

start_time=$(date +%s)
demucs-mlx "${INPUT_WAV}" --out "${OUTPUT_DIR}" -n htdemucs --prefetch-tracks 0 --write-workers 1
end_time=$(date +%s)

elapsed=$((end_time - start_time))
echo "Elapsed: ${elapsed}s"

expected=("vocals.wav" "drums.wav" "bass.wav" "other.wav")
missing=0
for stem in "${expected[@]}"; do
    if [[ ! -f "${OUTPUT_DIR}/sine/${stem}" ]]; then
        echo "MISSING: ${stem}"
        missing=1
    fi
done

if [[ ${missing} -ne 0 ]]; then
    echo "FAIL: not all expected stems were produced"
    exit 1
fi

echo "OK: live stem separation smoke passed"
