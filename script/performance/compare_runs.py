#!/usr/bin/env python3
"""Summarizes archive-launch JSON runs: one table row per metric, one column per label.

  python3 -I script/performance/compare_runs.py <directory> [label ...]

The directory holds files named <label>-<n>.json (one archive-launch run each). Labels default to
every label found, in alphabetical order. Each cell is the median across runs, with min-max and the
run count: "425 (410-450, n=5)". Times are milliseconds unless the row says otherwise.
"""
import json
import pathlib
import re
import statistics
import sys


def load(directory):
    runs = {}
    for path in sorted(directory.glob("*.json")):
        match = re.match(r"(.+)-(\d+)\.json$", path.name)
        if not match:
            continue
        try:
            runs.setdefault(match.group(1), []).append(json.loads(path.read_text()))
        except json.JSONDecodeError:
            continue
    return runs


def metrics(run):
    out = {}
    for key, value in run.get("timeline_ms", {}).items():
        out[f"launch: {key}"] = value
    for key in ("launch_main_cpu_ms", "launch_process_cpu_ms", "footprint_mib_after_launch", "footprint_mib_end"):
        if key in run:
            out[f"launch: {key}"] = run[key]
    for key, value in run.get("main_stalls_launch", {}).items():
        out[f"main stalls during launch: {key}"] = value
    for row in run.get("interactions", []):
        out[f"{row['scenario']} (median ms)"] = row["median_ms"]
    return out


def cell(values):
    if not values:
        return "-"
    values = sorted(values)
    return f"{statistics.median(values):.0f} ({values[0]:.0f}-{values[-1]:.0f}, n={len(values)})"


def main():
    directory = pathlib.Path(sys.argv[1])
    runs = load(directory)
    labels = sys.argv[2:] or sorted(runs)
    per_label = {label: [metrics(run) for run in runs.get(label, [])] for label in labels}
    names = []
    for label in labels:
        for run in per_label[label]:
            for name in run:
                if name not in names:
                    names.append(name)
    width = max((len(name) for name in names), default=10)
    print(f"{'metric':<{width}}  " + "  ".join(f"{label:>26}" for label in labels))
    for name in names:
        cells = [cell([run[name] for run in per_label[label] if name in run]) for label in labels]
        print(f"{name:<{width}}  " + "  ".join(f"{c:>26}" for c in cells))


if __name__ == "__main__":
    main()
