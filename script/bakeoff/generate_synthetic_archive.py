#!/usr/bin/env python3
"""Writes a deterministic synthetic Cubase archive for performance work.

Same seed and song count -> same folder names, files and mtimes. Nothing here
reads or touches a real archive: the output folder must not exist yet.

Layout per song (Cubase-ish, like Fixtures/CubaseArchive):
  <Song>/<Song>.cpr, <Song> v2.cpr ...      zero-byte project versions
  <Song>/Mixdown/*.wav                       tiny valid WAVs (mix, instr, versions)
  <Song>/Audio/*.wav                         recorded takes (some songs)
  <Song>/Stems/*.wav                         stem exports (some songs)
  <Song>/Auto Saves/<Song>-NN.bak            autosaves (some songs)

Song i is older than song i+1: the archive spans 2010 to 2026, so "older
content" means low indices / early years.
"""
import argparse
import os
import random
import struct
import sys
import time

ADJECTIVES = [
    "Amber", "Neon", "Velvet", "Hollow", "Golden", "Silent", "Electric", "Paper",
    "Midnight", "Broken", "Crystal", "Faded", "Wild", "Lucid", "Burning", "Frozen",
    "Glass", "Lonely", "Rapid", "Sacred", "Static", "Sugar", "Violet", "Wired",
    "Blue", "Copper", "Dusty", "Early", "Gentle", "Heavy", "Indigo", "Jaded",
]
NOUNS = [
    "Moth", "Hook", "Tide", "Signal", "Harbor", "Engine", "Garden", "Mirror",
    "River", "Satellite", "Echo", "Lantern", "Highway", "Island", "Ghost", "Pulse",
    "Comet", "Desert", "Fever", "Horizon", "Kingdom", "Machine", "Ocean", "Parade",
    "Rebel", "Shadow", "Thunder", "Vision", "Window", "Youth", "Zero", "Avenue",
]
COLLABORATORS = [
    "Lena", "Max", "Jules", "Mira", "Tobi", "Nora", "Elias", "Sami", "Ava",
    "Finn", "Lou", "Kai", "Rosa", "Ben", "Ida", "Theo",
]
MIX_NAMES = ["mix", "mixdown", "master", "preview", "bounce"]
ALT_NAMES = ["instr", "acapella", "ref", "old", "vox only"]
STEM_NAMES = [
    "Kick", "Snare", "HiHat", "Bass", "Synth", "Pad", "Lead Vox", "BG Vox",
    "FX", "Guitar", "Keys", "Perc", "Sub", "Strings",
]

START_EPOCH = int(time.mktime((2010, 1, 15, 12, 0, 0, 0, 0, -1)))
END_EPOCH = int(time.mktime((2026, 9, 30, 12, 0, 0, 0, 0, -1)))
DAY = 86400


def tiny_wav(frames):
    data = b"\x00\x00" * frames
    header = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, 44100, 88200, 2, 16)
    header += b"data" + struct.pack("<I", len(data))
    return header + data


def write(path, payload, mtime):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(payload)
    os.utime(path, (mtime, mtime))


def song_names(count, rng):
    seen = set()
    names = []
    for index in range(count):
        base = f"{rng.choice(ADJECTIVES)} {rng.choice(NOUNS)}"
        if rng.random() < 0.18:
            base += f" w {rng.choice(COLLABORATORS)}"
        name = base if base not in seen else f"{base} {index:05d}"
        seen.add(name)
        names.append(name)
    return names


def generate(out, count, seed):
    rng = random.Random(seed)
    archive = os.path.join(out, "CubaseArchive")
    os.makedirs(archive)
    mix_wav = tiny_wav(882)     # 20 ms
    short_wav = tiny_wav(441)   # 10 ms
    span = END_EPOCH - START_EPOCH
    files = 0
    for index, name in enumerate(song_names(count, rng)):
        song = os.path.join(archive, name)
        born = START_EPOCH + int(span * index / max(1, count)) + rng.randint(0, 20 * DAY)
        born = min(born, END_EPOCH - 60 * DAY)
        moment = born

        for version in range(1, rng.choice([1, 1, 2, 2, 3, 4, 6, 9]) + 1):
            moment += rng.randint(1, 21) * DAY
            label = f"{name}.cpr" if version == 1 else f"{name} v{version}.cpr"
            write(os.path.join(song, label), b"", moment)
            files += 1

        mixdown = os.path.join(song, "Mixdown")
        for take in range(1, rng.choice([1, 1, 2, 3, 4, 6]) + 1):
            moment += rng.randint(0, 7) * DAY
            suffix = rng.choice(MIX_NAMES)
            label = f"{name} {suffix}.wav" if take == 1 else f"{name} v{take} {suffix}.wav"
            write(os.path.join(mixdown, label), mix_wav, moment)
            files += 1
        if rng.random() < 0.35:
            write(os.path.join(mixdown, f"{name} {rng.choice(ALT_NAMES)}.wav"), mix_wav, moment)
            files += 1

        if rng.random() < 0.45:
            for take in range(rng.randint(4, 24)):
                write(os.path.join(song, "Audio", f"{name}_{take + 1:02d}.wav"), short_wav, born + take * 60)
                files += 1
        if rng.random() < 0.22:
            for stem in rng.sample(STEM_NAMES, rng.randint(5, 12)):
                write(os.path.join(song, "Stems", f"{name} {stem}.wav"), short_wav, moment)
                files += 1
        if rng.random() < 0.30:
            for backup in range(1, rng.randint(2, 6)):
                write(os.path.join(song, "Auto Saves", f"{name}-{backup:02d}.bak"), b"", born + backup * DAY)
                files += 1

        for directory, _, _ in os.walk(song, topdown=False):
            os.utime(directory, (moment, moment))
    os.utime(archive, (END_EPOCH, END_EPOCH))
    return archive, files


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--songs", type=int, required=True)
    parser.add_argument("--out", required=True, help="new folder; must not exist")
    parser.add_argument("--seed", type=int, default=20261018)
    args = parser.parse_args()
    out = os.path.abspath(args.out)
    if os.path.exists(out):
        sys.exit(f"refusing: {out} already exists")
    archive, files = generate(out, args.songs, args.seed)
    print(f"archive={archive} songs={args.songs} files={files} seed={args.seed}")


if __name__ == "__main__":
    main()
