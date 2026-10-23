#!/usr/bin/env python3
"""Star Abyss validation runner.

Python port of tools/verify.ps1 that runs on machines without PowerShell 7
(the original script requires `#Requires -Version 7.0` for ProcessStartInfo.ArgumentList).

Behaviour is intentionally identical to verify.ps1:
  * every explicit res:// reference must resolve to a file on disk;
  * each check is a separate Godot process with APPDATA redirected into the
    project so the user's real Godot editor settings are never touched;
  * a check fails on non-zero exit, or on SCRIPT ERROR/ERROR/FAIL lines.

Deviations, all deliberate and reported:
  * a small allowlist of environment-caused engine lines is ignored (see IGNORED_ERRORS);
    those lines come from the sandbox this project is validated in, not from the game;
  * `--json` writes a machine-readable summary for release gating;
  * `--only` runs a subset so a single failing suite can be iterated on quickly.

Usage:
    py tools/verify.py                       # full suite (needs a desktop session)
    py tools/verify.py --headless-only       # no window, no Forward+ rendering
    py tools/verify.py --only combat-rules,art-headless
    py tools/verify.py --json .local/validation/summary.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_GODOT = r"D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe"

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GAME_PATH = PROJECT_ROOT / "godot"
OUTPUT_PATH = PROJECT_ROOT / ".local" / "validation"
APPDATA_PATH = PROJECT_ROOT / ".local" / "appdata"
LOCALAPPDATA_PATH = PROJECT_ROOT / ".local" / "localappdata"

# Engine lines produced by the validation sandbox, not by the game.
#   * Windows certificate store is not readable in this environment;
#   * the editor settings save has no writable user directory when APPDATA is redirected.
IGNORED_ERRORS = (
    "Failed to read the root certificate store",
    "Can't save resource to empty path",
    "Error saving editor settings to",
)

ERROR_PATTERN = re.compile(r"(?im)^(SCRIPT ERROR:|ERROR:|FAIL:)")
RESULT_PATTERN = re.compile(r"^[ \t]*([A-Z0-9 _\-]*RESULT:.*)$", re.MULTILINE)
CHECK_PATTERN = re.compile(r"(\d+)\s+checks?,\s*(\d+)\s+failures?")


class Check:
    def __init__(self, name: str, args: list[str], graphical: bool, timeout: int = 300,
                 packed: bool = False, cwd: Path | None = None):
        self.name = name
        self.args = args
        self.graphical = graphical
        self.timeout = timeout
        self.packed = packed
        self.cwd = cwd


CHECKS: list[Check] = [
    Check("import", ["--headless", "--editor", "--import"], False, 600),
    Check("main-headless", ["--headless", "--fixed-fps", "60",
                            "--script", "res://tests/main_scene_smoke_test.gd"], False),
    Check("combat-rules", ["--headless", "--script", "res://tests/combat_rules_test.gd"], False),
    Check("enemy-rules", ["--headless", "--fixed-fps", "60",
                          "--script", "res://tests/enemy_rules_test.gd"], False),
    Check("enemy-behavior", ["--headless", "--fixed-fps", "60",
                             "--script", "res://tests/enemy_behavior_test.gd"], False),
    Check("blessing-rules", ["--headless", "--script", "res://tests/blessing_rules_test.gd"], False),
    Check("room-flow", ["--headless", "--fixed-fps", "60",
                        "--script", "res://tests/room_flow_test.gd"], False),
    Check("guardian-behavior", ["--headless", "--fixed-fps", "60",
                                "--script", "res://tests/guardian_behavior_test.gd"], False),
    Check("art-headless", ["--headless", "--fixed-fps", "60",
                           "--script", "res://tests/art_validation_test.gd"], False),
    Check("audio-feedback", ["--headless", "--fixed-fps", "60", "--audio-driver", "Dummy",
                             "--script", "res://tests/audio_feedback_test.gd"], False),
    Check("vfx-headless", ["--headless", "--fixed-fps", "60", "--audio-driver", "Dummy",
                           "--script", "res://tests/vfx_feedback_test.gd"], False),
    # Robustness (focus loss, repeated restart, card re-entry, UI contract). Headless is
    # sufficient: only the "focus release restores the cursor" assertion needs a real
    # window and skips itself with a printed reason. Windowed focus loss is still covered
    # end-to-end by the graphical integration suites and by tools/smoke_test.gd.
    Check("robustness", ["--headless", "--fixed-fps", "60", "--audio-driver", "Dummy",
                         "--script", "res://tests/robustness_test.gd"], False),
    # P8 design landing: proves each reviewed design item actually reached the game, with
    # one assertion group per item (see docs/DESIGN_REVIEW.md). Kept headless so it stays
    # deterministic and immune to the desktop-focus sensitivity of the graphical suites.
    Check("design-landing", ["--headless", "--fixed-fps", "60", "--audio-driver", "Dummy",
                             "--script", "res://tests/design_landing_test.gd"], False),
    # NOTE: export-smoke is intentionally NOT part of the default suites. It is an
    # external-PCK fixture (docs/BUILD_WINDOWS.md): it needs a finished .pck via
    # --main-pack, a real window with focus, and it asserts the pack excludes tests.
    # Running it from source, headless, or without a pack fails structurally, so it
    # is registered only when a pack is supplied with --packed <path>.
    # Graphical checks: real window, real Forward+ rendering, injected input.
    Check("main-window", ["--fixed-fps", "60", "--disable-vsync", "--audio-driver", "Dummy",
                          "--script", "res://tests/main_scene_smoke_test.gd"], True),
    Check("art-rendering", ["--fixed-fps", "60", "--disable-vsync", "--disable-render-loop",
                            "--audio-driver", "Dummy",
                            "--script", "res://tests/art_validation_test.gd"], True),
    Check("vfx-rendering", ["--fixed-fps", "60", "--disable-vsync", "--disable-render-loop",
                            "--audio-driver", "Dummy",
                            "--script", "res://tests/vfx_feedback_test.gd"], True),
    Check("input-physics", ["--fixed-fps", "60", "--disable-vsync", "--disable-render-loop",
                            "--audio-driver", "Dummy",
                            "--script", "../tools/smoke_test.gd"], True),
    Check("combat-integration", ["--fixed-fps", "60", "--disable-vsync", "--disable-render-loop",
                                 "--audio-driver", "Dummy",
                                 "--script", "res://tests/combat_integration_test.gd"], True),
    Check("enemy-integration", ["--fixed-fps", "60", "--disable-vsync", "--disable-render-loop",
                                "--audio-driver", "Dummy",
                                "--script", "res://tests/enemy_integration_test.gd"], True),
    Check("room-integration", ["--fixed-fps", "60", "--disable-vsync", "--disable-render-loop",
                               "--audio-driver", "Dummy",
                               "--script", "res://tests/room_integration_test.gd"], True),
    Check("full-run-integration", ["--fixed-fps", "60", "--disable-vsync", "--disable-render-loop",
                                   "--audio-driver", "Dummy",
                                   "--script", "res://tests/full_run_integration_test.gd"], True, 900),
    Check("performance", ["--fixed-fps", "60", "--disable-vsync", "--audio-driver", "Dummy",
                          "--script", "res://tests/performance_benchmark.gd"], True, 900),
]

REFERENCE_SUFFIXES = {".godot", ".gd", ".tscn", ".tres"}
REFERENCE_PATTERN = re.compile(r'res://[^"\s\)\]]+')


def validate_references() -> int:
    """Every explicit res:// path in project sources must exist on disk."""
    count = 0
    problems: list[str] = []
    for path in GAME_PATH.rglob("*"):
        if not path.is_file() or path.suffix not in REFERENCE_SUFFIXES:
            continue
        if ".godot" in path.parts:
            continue
        try:
            source = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:  # pragma: no cover - unreadable file is a real failure
            problems.append(f"unreadable {path}: {exc}")
            continue
        for match in REFERENCE_PATTERN.finditer(source):
            target = GAME_PATH / match.group(0)[6:]
            if not target.exists():
                rel = path.relative_to(PROJECT_ROOT)
                problems.append(f"missing reference in {rel}: {match.group(0)}")
            count += 1
    if problems:
        for problem in problems:
            print(f"FAIL: {problem}")
        raise SystemExit(f"FAIL: {len(problems)} of {count} resource references do not resolve")
    print(f"PASS: {count} resource references resolve")
    return count


def classify(output: str) -> list[str]:
    """Return genuine engine error lines, ignoring sandbox-caused noise."""
    failures: list[str] = []
    for line in output.splitlines():
        if not ERROR_PATTERN.match(line):
            continue
        if any(ignored in line for ignored in IGNORED_ERRORS):
            continue
        failures.append(line.strip())
    return failures


def run_check(check: Check, godot: str, cwd: Path | None = None) -> dict:
    log_path = OUTPUT_PATH / f"{check.name}.log"
    work_dir = cwd if cwd is not None else PROJECT_ROOT
    project_args: list[str] = [] if check.packed else ["--path", str(GAME_PATH)]
    cmd = [godot, *project_args, "--log-file", str(log_path), "--max-fps", "0", *check.args]
    env = dict(os.environ)
    # Redirect both user-data roots: APPDATA holds editor settings, LOCALAPPDATA holds
    # the editor cache directory. Redirecting only APPDATA still makes Godot attempt
    # C:/Users/<user>/AppData/Local/Godot and emit "Could not create editor cache
    # directory" errors during --import, which would fail the import check.
    env["APPDATA"] = str(APPDATA_PATH)
    env["LOCALAPPDATA"] = str(LOCALAPPDATA_PATH)
    started = time.time()
    try:
        completed = subprocess.run(
            cmd, cwd=str(PROJECT_ROOT), env=env, capture_output=True,
            timeout=check.timeout, text=True, encoding="utf-8", errors="replace",
        )
        output = (completed.stdout or "") + (completed.stderr or "")
        code = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        output = ((exc.stdout or b"").decode("utf-8", "replace")
                  + (exc.stderr or b"").decode("utf-8", "replace")) if isinstance(exc.stdout, bytes) else (exc.stdout or "") + (exc.stderr or "")
        code = -1
        timed_out = True

    (OUTPUT_PATH / f"{check.name}.output.txt").write_text(output, encoding="utf-8")

    engine_log = ""
    if log_path.exists():
        engine_log = log_path.read_text(encoding="utf-8", errors="replace")

    failures = classify(output) + classify(engine_log)
    result_lines = [m.group(1).strip() for m in RESULT_PATTERN.finditer(output)]
    checks_total = checks_failed = 0
    for line in result_lines:
        match = CHECK_PATTERN.search(line)
        if match:
            checks_total += int(match.group(1))
            checks_failed += int(match.group(2))

    ok = code == 0 and not failures and not timed_out and checks_failed == 0
    verdict = "PASS" if ok else "FAIL"
    elapsed = round(time.time() - started, 1)
    print(f"{verdict}: {check.name} (exit {code}, {elapsed}s"
          + (f", {checks_total} checks, {checks_failed} failures" if checks_total else "") + ")")
    for line in result_lines:
        print(f"  {line}")
    for failure in failures[:20]:
        print(f"  ! {failure}")
    if timed_out:
        print(f"  ! timed out after {check.timeout}s")

    return {
        "name": check.name,
        "graphical": check.graphical,
        "status": verdict,
        "exit_code": code,
        "timed_out": timed_out,
        "seconds": elapsed,
        "checks": checks_total,
        "failures": checks_failed,
        "error_lines": failures[:20],
        "result_lines": result_lines,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Star Abyss validation runner")
    parser.add_argument("--godot", default=os.environ.get("STARABYSS_GODOT", DEFAULT_GODOT))
    parser.add_argument("--headless-only", action="store_true",
                        help="skip graphical suites that need a desktop session")
    parser.add_argument("--only", default="", help="comma separated check names")
    parser.add_argument("--json", default="", help="write summary JSON to this path")
    parser.add_argument("--no-references", action="store_true", help="skip reference validation")
    parser.add_argument("--packed", default="",
                        help="path to a finished .pck; registers the external-PCK export smoke check "
                             "and runs it as its own graphical suite")
    args = parser.parse_args()

    if not Path(args.godot).is_file():
        print(f"FATAL: Godot executable not found: {args.godot}", file=sys.stderr)
        return 2

    OUTPUT_PATH.mkdir(parents=True, exist_ok=True)
    APPDATA_PATH.mkdir(parents=True, exist_ok=True)
    LOCALAPPDATA_PATH.mkdir(parents=True, exist_ok=True)

    packed_checks: list[Check] = []
    if args.packed:
        pack_path = Path(args.packed).resolve()
        if not pack_path.is_file():
            print(f"FATAL: pack not found: {pack_path}", file=sys.stderr)
            return 2
        fixture = (GAME_PATH / "tests" / "export_smoke_test.gd").resolve()
        audit = (PROJECT_ROOT / "tools" / "pack_audit.gd").resolve()
        screenshot = OUTPUT_PATH / "export_smoke_screenshot.png"
        # Content audit first: cheap, headless, no window, and it fails loudly when a
        # cue/model/scene is missing from the pack or a development test leaked in.
        packed_checks.append(Check(
            "pack-audit",
            ["--headless", "--main-pack", str(pack_path),
             "--audio-driver", "Dummy", "--script", str(audit)],
            graphical=False, timeout=180, packed=True, cwd=pack_path.parent,
        ))
        # Then the real packed-data game fixture, which needs a window for pointer
        # input and mouse capture.
        packed_checks.append(Check(
            "export-smoke",
            ["--main-pack", str(pack_path),
             "--fixed-fps", "60", "--disable-vsync", "--audio-driver", "Dummy",
             "--script", str(fixture), "--", str(screenshot)],
            graphical=True, timeout=300, packed=True, cwd=pack_path.parent,
        ))

    selected = [name.strip() for name in args.only.split(",") if name.strip()]
    all_checks = CHECKS + packed_checks
    if selected:
        unknown = set(selected) - {c.name for c in all_checks}
        if unknown:
            print(f"FATAL: unknown check(s): {', '.join(sorted(unknown))}", file=sys.stderr)
            return 2
    plan = [c for c in all_checks if (not selected or c.name in selected)]
    if args.headless_only:
        plan = [c for c in plan if not c.graphical]

    print(f"Godot: {args.godot}")
    print(f"Project: {GAME_PATH}")
    print(f"Checks: {len(plan)}" + (" (headless only)" if args.headless_only else ""))
    print("-" * 72)

    references = 0
    if not args.no_references:
        try:
            references = validate_references()
        except SystemExit as exc:
            print(exc)
            return 1

    started = time.time()
    results = [run_check(check, args.godot, check.cwd) for check in plan]
    if args.headless_only:
        print("SKIP: graphical input/physics suite and Forward+ rendering; "
              "they require a desktop session. Run without --headless-only to cover them.")

    total_checks = sum(r["checks"] for r in results)
    total_failures = sum(r["failures"] for r in results)
    failed = [r for r in results if r["status"] != "PASS"]
    summary = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "godot": args.godot,
        "project": str(GAME_PATH),
        "headless_only": args.headless_only,
        "resource_references": references,
        "assertions": total_checks,
        "assertion_failures": total_failures,
        "checks_run": len(results),
        "checks_failed": len(failed),
        "seconds": round(time.time() - started, 1),
        "status": "PASS" if not failed else "FAIL",
        "results": results,
    }
    print("-" * 72)
    print(f"{summary['status']}: {len(results) - len(failed)}/{len(results)} checks, "
          f"{total_checks} assertions, {total_failures} assertion failures, "
          f"{summary['seconds']}s")

    if args.json:
        target = Path(args.json)
        if not target.is_absolute():
            target = PROJECT_ROOT / target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"summary written to {target}")

    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
