#!/usr/bin/env python3
"""Objective screenshot checks for Star Abyss.

The validation agents can produce PNGs, but "a PNG exists" proves very little: a
black frame, a frame of pure UI chrome, or two identical frames would all pass a
file-existence test. This script measures what is actually on screen so the
release report can claim "the game renders real content" with numbers.

Per image it reports:
  * pixel dimensions and aspect ratio;
  * mean / std of luminance and the fraction of near-black pixels (blank-frame detector);
  * distinct quantised colours (a flat UI panel has very few; a 3D scene has thousands);
  * a coarse 8x8 luminance signature, used to compare frames against each other.

Pairwise it reports the mean absolute difference between frames, which lets a test
assert "pressing a key changed the picture" or "the boss telegraph actually drew
something different from idle".

Usage:
    py tools/screenshot_check.py docs/*.png
    py tools/screenshot_check.py --json out.json docs/main_menu_preview.png
    py tools/screenshot_check.py --diff a.png b.png
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover - environment guard
    print(f"FATAL: needs Pillow and numpy: {exc}", file=sys.stderr)
    raise SystemExit(2)


def load(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.float64)


def luminance(pixels: np.ndarray) -> np.ndarray:
    return pixels @ np.array([0.2126, 0.7152, 0.0722])


def signature(pixels: np.ndarray, cells: int = 8) -> list[float]:
    """Coarse brightness grid, scale independent, for frame comparison."""
    lum = luminance(pixels)
    rows = np.array_split(lum, cells, axis=0)
    grid = []
    for row in rows:
        for cell in np.array_split(row, cells, axis=1):
            grid.append(round(float(cell.mean()), 2))
    return grid


def describe(path: Path) -> dict:
    pixels = load(path)
    lum = luminance(pixels)
    height, width = lum.shape
    # Quantise to 4 bits per channel: flat UI regions collapse, rendered 3D does not.
    quantised = (pixels // 16).astype(np.uint8)
    flat = quantised.reshape(-1, 3)
    distinct = len(np.unique(flat, axis=0))
    return {
        "path": str(path),
        "width": int(width),
        "height": int(height),
        "aspect": round(width / height, 4),
        "luminance_mean": round(float(lum.mean()), 2),
        "luminance_std": round(float(lum.std()), 2),
        "near_black_fraction": round(float((lum < 8.0).mean()), 4),
        "distinct_colors_4bit": int(distinct),
        "bytes": path.stat().st_size,
        "signature": signature(pixels),
        "blank_suspect": bool(lum.std() < 3.0 or distinct < 12),
    }


def diff(path_a: Path, path_b: Path) -> dict:
    a, b = load(path_a), load(path_b)
    if a.shape != b.shape:
        return {"a": str(path_a), "b": str(path_b), "comparable": False,
                "reason": f"size mismatch {a.shape[1]}x{a.shape[0]} vs {b.shape[1]}x{b.shape[0]}"}
    delta = np.abs(a - b).mean(axis=2)
    return {
        "a": str(path_a),
        "b": str(path_b),
        "comparable": True,
        "mean_abs_diff": round(float(delta.mean()), 3),
        "changed_pixel_fraction": round(float((delta > 6.0).mean()), 4),
        "identical": bool(delta.mean() < 0.5),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Objective screenshot statistics")
    parser.add_argument("images", nargs="*", help="PNG files to describe")
    parser.add_argument("--diff", nargs=2, metavar=("A", "B"), help="compare two images")
    parser.add_argument("--json", default="", help="write results as JSON")
    args = parser.parse_args()

    report: dict = {"images": [], "diff": None}
    for raw in args.images:
        path = Path(raw)
        if not path.is_file():
            print(f"FAIL: missing image {path}")
            report["images"].append({"path": str(path), "missing": True})
            continue
        info = describe(path)
        report["images"].append(info)
        flag = " [BLANK?]" if info["blank_suspect"] else ""
        print(f"{path.name:<34} {info['width']:>5}x{info['height']:<5} "
              f"lum {info['luminance_mean']:>6.1f}±{info['luminance_std']:<6.2f} "
              f"colours {info['distinct_colors_4bit']:>6} "
              f"black {info['near_black_fraction']*100:>5.1f}%{flag}")

    if args.diff:
        info = diff(Path(args.diff[0]), Path(args.diff[1]))
        report["diff"] = info
        if not info["comparable"]:
            print(f"DIFF not comparable: {info['reason']}")
        else:
            print(f"DIFF {Path(args.diff[0]).name} vs {Path(args.diff[1]).name}: "
                  f"mean {info['mean_abs_diff']} changed {info['changed_pixel_fraction']*100:.1f}% "
                  f"identical={info['identical']}")

    blanks = [i["path"] for i in report["images"] if i.get("blank_suspect")]
    if blanks:
        print(f"FAIL: {len(blanks)} image(s) look blank: {', '.join(blanks)}")
    if args.json:
        target = Path(args.json)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"written {target}")
    return 1 if blanks else 0


if __name__ == "__main__":
    sys.exit(main())
