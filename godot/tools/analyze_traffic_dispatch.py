"""Summarize raw AB/BA dispatch probe timings; this does not estimate FPS."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import statistics


def summarize(log: Path) -> dict:
    lines = log.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    prefix = "[traffic_dispatch] TIMINGS "
    rows = json.loads(next(line[len(prefix):] for line in lines if line.startswith(prefix)))
    gates = {}
    for scenario in sorted({row["scenario"] for row in rows}):
        samples = [row for row in rows if row["scenario"] == scenario]
        gates[str(scenario)] = {
            "pairs": len(samples),
            "baseline_median_usec_per_call": statistics.median(row["baseline_usec"] / row["calls"] for row in samples),
            "candidate_median_usec_per_call": statistics.median(row["candidate_usec"] / row["calls"] for row in samples),
            "median_paired_change_percent": statistics.median((row["candidate_usec"] / row["baseline_usec"] - 1) * 100 for row in samples),
            "candidate_faster_pairs": sum(row["candidate_usec"] < row["baseline_usec"] for row in samples),
        }
    return {"source": str(log.resolve()), "gates": gates, "raw_pairs": rows,
            "notes": "Same-process alternating AB/BA control dispatch microbenchmark; fixture arrangement is synthetic. No FPS or whole-world gain follows from these numbers. Inspect functional pass/error log separately."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = summarize(args.log)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result["gates"], indent=2))
