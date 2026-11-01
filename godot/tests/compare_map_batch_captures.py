"""Compare map probe captures; preserve numeric evidence and amplified diffs.

Usage: python godot/tests/compare_map_batch_captures.py artifacts/priorities-five/map-batch
Pixel metrics are evidence for review, not a substitute for geometry assertions.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def main(directory: Path) -> None:
    results = []
    for baseline in sorted(directory.glob("legacy-*.png")):
        current = directory / baseline.name.replace("legacy-", "current-", 1)
        before = Image.open(baseline).convert("RGB")
        after = Image.open(current).convert("RGB")
        if before.size != after.size:
            raise ValueError(f"Capture size mismatch: {baseline.name}")
        delta = ImageChops.difference(before, after)
        changed = sum(any(pixel) for pixel in delta.getdata())
        results.append({"view": baseline.stem.removeprefix("legacy-"),
                        "pixels": before.width * before.height,
                        "changed_pixels": changed,
                        "changed_fraction": changed / (before.width * before.height),
                        "mean_absolute_rgb": sum(ImageStat.Stat(delta).mean) / 3,
                        "max_channel_delta": max(high for _, high in delta.getextrema())})
        delta.point(lambda value: min(value * 4, 255)).save(
            directory / baseline.name.replace("legacy-", "difference-x4-", 1))
    (directory / "capture-comparison.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main(Path(sys.argv[1]))
