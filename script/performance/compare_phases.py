#!/usr/bin/env python3
"""Summarizes archive-startup JSON runs written by ab.sh: one row per phase, one column per tag.

  python3 -I script/performance/compare_phases.py <directory> <tagA> <tagB> [...]

Each cell pools the samples of every run of that tag: median wall ms (min-max, n samples) and median
process CPU ms. The last column says whether the output digests of both tags match (the same data came
back) and the wall-time ratio of the first tag over the last.
"""
import json
import pathlib
import re
import statistics
import sys


def load(directory, tags):
    pooled = {tag: {} for tag in tags}
    digests = {tag: {} for tag in tags}
    for path in sorted(directory.glob("*.json")):
        match = re.match(r"(.+)-(\d+)\.json$", path.name)
        if not match or match.group(1) not in pooled:
            continue
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
        for result in data.get("results", []):
            slot = pooled[match.group(1)].setdefault(result["name"], {"wall": [], "cpu": []})
            slot["wall"].extend(result["samples_ms"])
            slot["cpu"].extend(result.get("cpu_samples_ms", []))
            digest = result.get("detail", {}).get("digest")
            if digest:
                digests[match.group(1)].setdefault(result["name"], set()).add(digest)
    return pooled, digests


def main():
    directory = pathlib.Path(sys.argv[1])
    tags = sys.argv[2:]
    pooled, digests = load(directory, tags)
    names = []
    for tag in tags:
        for name in pooled[tag]:
            if name not in names:
                names.append(name)
    print(f"{'phase':<28}" + "".join(f" | {tag:<44}" for tag in tags) + " | digest    ratio")
    for name in names:
        cells = []
        medians = []
        for tag in tags:
            slot = pooled[tag].get(name)
            if not slot or not slot["wall"]:
                cells.append("-")
                medians.append(None)
                continue
            wall = sorted(slot["wall"])
            cpu = statistics.median(slot["cpu"]) if slot["cpu"] else 0
            medians.append(statistics.median(wall))
            cells.append(f"{statistics.median(wall):.1f} ({wall[0]:.1f}-{wall[-1]:.1f}, n={len(wall)}) cpu {cpu:.0f}")
        seen = [digests[tag].get(name) for tag in tags if digests[tag].get(name)]
        digest = "-" if not seen else ("same" if all(s == seen[0] and len(s) == 1 for s in seen) else "DIFFERENT")
        ratio = f"{medians[0] / medians[-1]:.2f}x" if medians[0] and medians[-1] else "-"
        print(f"{name:<28}" + "".join(f" | {cell:<44}" for cell in cells) + f" | {digest:<9} {ratio}")


if __name__ == "__main__":
    main()
