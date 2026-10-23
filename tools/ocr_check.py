#!/usr/bin/env python3
"""Extract on-screen text from Star Abyss screenshots with the Windows OCR engine.

Purpose
-------
No agent working on this project has image input, so "the UI element is visible" used to be
verifiable only as "some pixels changed". Windows ships a Chinese OCR engine
(Windows.Media.Ocr, ``zh-Hans-CN`` on this machine), which lets QA compare the text that is
*actually rendered* against the string literals in source.

This tool is mechanical evidence, NOT human playtest: it proves a string was drawn, not that a
human could read it comfortably, nor anything about feel/balance/run length.

Usage
-----
    py tools\\ocr_check.py shots\\*.png                        # recognise, print text
    py tools\\ocr_check.py room.png --expect "完美闪避"        # assert a string appears
    py tools\\ocr_check.py room.png --expect-from-source run_ui.gd:348
    py tools\\ocr_check.py room.png --json out.json --show-diff

Exit code is 0 when every ``--expect`` string was found, 1 otherwise, so it can gate a suite.

Notes
-----
* OCR inserts spaces between CJK glyphs ("探 索 者 已 倒 下"); comparison therefore strips all
  whitespace. Full-width punctuation (``：／·–``) is normalised too, because CJK OCR commonly
  confuses those; per-string raw-vs-normalised results are reported separately so a mismatch
  caused by normalisation is visible instead of silently "fixed".
* Recognition needs the PowerShell helper ``tools/ocr_winrt.ps1`` (WinRT plumbing); this file
  does all UTF-8 text handling and comparison so console code pages never touch the data.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ocr_winrt.ps1")

# Full-width / typographic variants that CJK OCR regularly confuses.
_PUNCT_MAP = {
    "：": ":", "；": ";", "，": ",", "。": ".", "、": ",",
    "（": "(", "）": ")", "／": "/", "·": ".", "・": ".", "．": ".",
    "—": "-", "–": "-", "－": "-", "〜": "~", "～": "~",
    "〔": "[", "〕": "]", "【": "[", "】": "]",
    "％": "%", "＋": "+", "＝": "=",
}


def strip_ws(text: str) -> str:
    return re.sub(r"\s+", "", text or "")


def normalise(text: str) -> str:
    out = []
    for ch in strip_ws(text):
        out.append(_PUNCT_MAP.get(ch, ch))
    return "".join(out)


def run_ocr(images: list[str], scale: int) -> dict:
    """OCR the given files by driving the PowerShell WinRT helper one folder at a time."""
    by_dir: dict[str, list[str]] = {}
    for path in images:
        by_dir.setdefault(os.path.dirname(os.path.abspath(path)) or ".", []).append(
            os.path.basename(path)
        )

    merged: dict[str, dict] = {}
    engine_language = None
    for folder, names in by_dir.items():
        # The helper takes Dir+Pattern (a path list cannot survive `powershell -File`), so run
        # once per folder and once per name pattern.
        for name in names:
            fd, out_json = tempfile.mkstemp(suffix=".json", prefix="ocr_")
            os.close(fd)
            try:
                cmd = [
                    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                    "-File", HELPER,
                    "-Dir", folder,
                    "-Pattern", name,
                    "-Scale", str(scale),
                    "-OutJson", out_json,
                ]
                proc = subprocess.run(cmd, capture_output=True, text=True,
                                      encoding="utf-8", errors="replace")
                if proc.returncode != 0:
                    raise RuntimeError(
                        f"ocr helper failed for {name} (exit {proc.returncode}): "
                        f"{(proc.stderr or proc.stdout or '').strip()[:400]}"
                    )
                with open(out_json, "r", encoding="utf-8") as handle:
                    payload = json.load(handle)
                engine_language = payload.get("engine_language", engine_language)
                for item in payload.get("results", []):
                    merged[os.path.abspath(item["file"])] = item
            finally:
                if os.path.exists(out_json):
                    os.remove(out_json)

    return {"engine_language": engine_language, "results": merged}


def source_literal(path: str, line: int | None) -> str:
    """Pull the Chinese string literal out of a .gd file (optionally at a given line)."""
    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()
    if line is not None:
        window = [lines[line - 1]] if 0 < line <= len(lines) else []
    else:
        window = lines
    for text in window:
        match = re.search(r'"([^"\n]*[\u4e00-\u9fff][^"\n]*)"', text)
        if match:
            return match.group(1)
    raise SystemExit(f"no Chinese string literal found in {path}"
                     + (f":{line}" if line else ""))


def check(expectations: list[tuple[str, str, dict]], results: dict, show_diff: bool) -> int:
    """Compare expectations against recognised text; print a per-expectation verdict."""
    failures = 0
    for image, want, meta in expectations:
        item = results.get(os.path.abspath(image))
        seen = item.get("text", "") if item else ""
        raw_hit = want in seen
        strip_hit = strip_ws(want) in strip_ws(seen)
        norm_hit = normalise(want) in normalise(seen)

        if norm_hit:
            verdict = "PASS"
        else:
            verdict = "FAIL"
            failures += 1

        print(f"{verdict}: {os.path.basename(image)} contains {want!r}")
        print(f"       exact={raw_hit} whitespace-insensitive={strip_hit} "
              f"normalised={norm_hit} (source: {meta.get('source', 'cli')})")
        if not norm_hit or show_diff:
            print(f"       recognised text: {strip_ws(seen)[:400]!r}")
    return failures


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="OCR screenshots and compare with source strings")
    parser.add_argument("images", nargs="+", help="screenshot path(s) or glob(s)")
    parser.add_argument("--expect", action="append", default=[],
                        help="string that must appear on screen (repeatable)")
    parser.add_argument("--expect-from-source", action="append", default=[],
                        metavar="FILE[:LINE]",
                        help="take the expected string from a .gd literal (repeatable)")
    parser.add_argument("--scale", type=int, default=2, help="upscale factor before OCR (default 2)")
    parser.add_argument("--json", dest="json_out", help="write recognised text + verdicts as JSON")
    parser.add_argument("--show-diff", action="store_true",
                        help="always print the recognised text, not only on mismatch")
    parser.add_argument("--text-only", action="store_true", help="only print recognised text")
    args = parser.parse_args(argv)

    images: list[str] = []
    for spec in args.images:
        hits = glob.glob(spec)
        images.extend(hits if hits else [spec])
    missing = [p for p in images if not os.path.isfile(p)]
    if missing:
        parser.error(f"not found: {missing}")

    ocr = run_ocr(images, args.scale)
    results = ocr["results"]

    if args.json_out:
        payload = {
            "tool": "tools/ocr_check.py",
            "engine_language": ocr["engine_language"],
            "note": "mechanical OCR evidence; not evidence of human readability or playtest",
            "results": [
                {
                    "file": path,
                    "lines": results[path]["lines"],
                    "text": results[path]["text"],
                }
                for path in sorted(results)
            ],
        }
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)

    if args.text_only:
        for path in sorted(results):
            print(f"=== {os.path.basename(path)} ===")
            for line in results[path]["lines"] or ["(no text recognised)"]:
                print("  " + line)
        return 0

    expectations: list[tuple[str, str, dict]] = []
    for want in args.expect:
        for image in images:
            expectations.append((image, want, {"source": "cli --expect"}))
    for spec in args.expect_from_source:
        path, _, line_txt = spec.partition(":")
        literal = source_literal(path, int(line_txt) if line_txt else None)
        resolved = os.path.abspath(path)
        for image in images:
            expectations.append((image, literal, {"source": f"{resolved}:{line_txt or '*'}"}))

    if not expectations:
        for path in sorted(results):
            print(f"=== {os.path.basename(path)} ===")
            for line in results[path]["lines"] or ["(no text recognised)"]:
                print("  " + line)
        return 0

    failures = check(expectations, results, args.show_diff)
    print(f"\n{len(expectations) - failures}/{len(expectations)} expectations met "
          f"(engine {ocr['engine_language']})")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
