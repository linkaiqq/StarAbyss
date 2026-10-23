#!/usr/bin/env python3
"""Measure how long the released game takes to put a real picture on screen.

Why this exists: "the exe starts" is not a launch-quality measurement. A player
sees three distinct phases, and only the last one is usable:

  1. process launch      -> a window exists (may still be blank/white/black)
  2. first painted frame -> the engine submitted something, possibly a clear colour
  3. first real frame    -> non-uniform content, i.e. the menu is actually visible

Phase 2->3 is where a shader-compilation stall shows up as a frozen, featureless
window. This probe reports each transition with timings taken from the real screen,
so the number in the report is what a player would actually experience.

It finds the window by process id (not by title), grabs the client area, and
classifies frames by luminance statistics. Nothing is injected into the game.

Usage:
    py tools/startup_probe.py --exe builds/windows/star_abyss_windows_x64/StarAbyss.exe
    py tools/startup_probe.py --exe ... --runs 2 --json out.json
    py tools/startup_probe.py --exe ... --timeout 25 --keep-open
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.wintypes as wt
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

try:
    import numpy as np
    from PIL import ImageGrab
except ImportError as exc:  # pragma: no cover
    print(f"FATAL: needs Pillow and numpy: {exc}", file=sys.stderr)
    raise SystemExit(2)

user32 = ctypes.windll.user32
try:
    user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))  # PER_MONITOR_AWARE_V2
except Exception:
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        pass


def window_for_pid(pid: int) -> int:
    """Return the first top-level, visible window belonging to pid."""
    found: list[int] = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def callback(hwnd, _lparam):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            rect = wt.RECT()
            if user32.GetClientRect(hwnd, ctypes.byref(rect)) and rect.right - rect.left > 200:
                found.append(hwnd)
                return False
        return True

    user32.EnumWindows(callback, 0)
    return found[0] if found else 0


def client_screen_rect(hwnd: int) -> tuple[int, int, int, int]:
    rect = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    origin = wt.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(origin))
    return (origin.x, origin.y, origin.x + rect.right, origin.y + rect.bottom)


SW_RESTORE = 9
VK_MENU = 0x12
KEYEVENTF_KEYUP = 0x0002


def raise_window(hwnd: int) -> bool:
    """Bring the game window to the front and confirm it is the foreground window.

    Without this, a screen grab of the client rect returns whatever window happens to
    be on top - which is how a first measurement of this probe reported a flat
    luminance of 244 (a white application window) as if it were the game's boot frame.

    Windows blocks SetForegroundWindow from a process that does not own the current
    foreground, so we first press a synthetic ALT to release that restriction, which is
    the usual workaround. SwitchToThisWindow is the fallback.
    """
    user32.ShowWindow(hwnd, SW_RESTORE)
    user32.keybd_event(VK_MENU, 0, 0, 0)
    user32.SetForegroundWindow(hwnd)
    user32.keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0)
    if user32.GetForegroundWindow() != hwnd:
        user32.SwitchToThisWindow(hwnd, True)
    for _ in range(20):
        if user32.GetForegroundWindow() == hwnd:
            return True
        time.sleep(0.05)
    return user32.GetForegroundWindow() == hwnd


def frame_stats(bbox: tuple[int, int, int, int]) -> tuple[float, int]:
    """Mean luminance and distinct 4-bit colour count of the captured region."""
    try:
        image = ImageGrab.grab(bbox=bbox, all_screens=False)
    except Exception:
        return 0.0, 0
    pixels = np.asarray(image.convert("RGB"), dtype=np.float64)
    if pixels.size == 0:
        return 0.0, 0
    lum = pixels @ np.array([0.2126, 0.7152, 0.0722])
    quantised = (pixels // 16).astype(np.uint8).reshape(-1, 3)
    return float(lum.mean()), int(len(np.unique(quantised, axis=0)))


def one_run(exe: Path, timeout: float, keep_open: bool, poll: float) -> dict:
    started = time.perf_counter()
    process = subprocess.Popen(
        [str(exe)],
        cwd=str(exe.parent),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    result = {
        "exe": str(exe),
        "pid": process.pid,
        "window_appeared_ms": None,
        "first_frame_any_ms": None,
        "first_non_white_ms": None,
        "first_menu_like_ms": None,
        "stable_menu_ms": None,
        "samples": [],
    }
    hwnd = 0
    bbox = None
    consecutive_menu = 0
    try:
        while time.perf_counter() - started < timeout:
            elapsed = (time.perf_counter() - started) * 1000.0
            if not hwnd:
                hwnd = window_for_pid(process.pid)
                if hwnd:
                    result["window_appeared_ms"] = round(elapsed, 1)
                    bbox = client_screen_rect(hwnd)
                    result["foreground"] = raise_window(hwnd)
                else:
                    time.sleep(poll)
                    continue
            lum, colours = frame_stats(bbox)
            if len(result["samples"]) < 600:
                result["samples"].append({"ms": round(elapsed, 1), "lum": round(lum, 2), "colours": colours})

            # The engine paints something at all (could be a white boot flash).
            if result["first_frame_any_ms"] is None and (lum > 1.0 or colours > 2):
                result["first_frame_any_ms"] = round(elapsed, 1)
            # Left the blank-white startup state.
            if result["first_non_white_ms"] is None and lum < 200.0 and colours > 2:
                result["first_non_white_ms"] = round(elapsed, 1)
            # Looks like the dark menu/UI rather than a flash: the shipped main menu
            # measures ~25 luminance with >100 quantised colours.
            menu_like = 6.0 < lum < 200.0 and colours >= 40
            if menu_like:
                consecutive_menu += 1
                if result["first_menu_like_ms"] is None:
                    result["first_menu_like_ms"] = round(elapsed, 1)
                if consecutive_menu >= 3 and result["stable_menu_ms"] is None:
                    result["stable_menu_ms"] = round(elapsed, 1)
                    break
            else:
                consecutive_menu = 0
            time.sleep(poll)
    finally:
        if not keep_open and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
    result["client_rect"] = list(bbox) if bbox else None
    result["exited"] = process.poll()
    # A readable progression so the report can show what the player actually saw.
    samples = result["samples"]
    if samples:
        step = max(1, len(samples) // 12)
        result["progression"] = [samples[i] for i in range(0, len(samples), step)]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Measure launch-to-first-frame latency")
    parser.add_argument("--exe", required=True, help="path to the released StarAbyss.exe")
    parser.add_argument("--runs", type=int, default=1, help="number of launches")
    parser.add_argument("--timeout", type=float, default=25.0, help="per-run timeout in seconds")
    parser.add_argument("--poll", type=float, default=0.05, help="sampling interval in seconds")
    parser.add_argument("--keep-open", action="store_true", help="leave the game running")
    parser.add_argument("--json", default="", help="write results as JSON")
    args = parser.parse_args()

    exe = Path(args.exe).resolve()
    if not exe.is_file():
        print(f"FAIL: no such exe {exe}")
        return 2

    runs = []
    print(f"exe: {exe}")
    print(f"{'run':>3} {'window_ms':>10} {'any_frame':>10} {'non_white':>10} {'menu_like':>10} {'stable_menu':>12}")
    for index in range(args.runs):
        result = one_run(exe, args.timeout, args.keep_open, args.poll)
        runs.append(result)
        print(f"{index + 1:>3} {str(result['window_appeared_ms']):>10} "
              f"{str(result['first_frame_any_ms']):>10} "
              f"{str(result['first_non_white_ms']):>10} "
              f"{str(result['first_menu_like_ms']):>10} "
              f"{str(result['stable_menu_ms']):>12}")
        for sample in result.get("progression", [])[:12]:
            print(f"      {sample['ms']:>8.1f} ms  lum {sample['lum']:>7.2f}  colours {sample['colours']:>4}")
        if args.keep_open:
            break
        time.sleep(1.0)

    stable = [r["stable_menu_ms"] for r in runs if r["stable_menu_ms"] is not None]
    summary = {
        "runs": runs,
        "stable_menu_ms": stable,
        "median_stable_menu_ms": round(statistics.median(stable), 1) if stable else None,
        "failures": len(runs) - len(stable),
    }
    print("")
    if stable:
        print(f"stable usable frame: median {summary['median_stable_menu_ms']} ms over {len(stable)} run(s)")
    if summary["failures"]:
        print(f"FAIL: {summary['failures']} run(s) never showed a stable usable frame within {args.timeout}s")
    if args.json:
        target = Path(args.json)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(f"written {target}")
    return 1 if summary["failures"] else 0


if __name__ == "__main__":
    sys.exit(main())
