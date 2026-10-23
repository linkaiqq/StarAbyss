#!/usr/bin/env python3
"""Star Abyss Windows x64 release build pipeline.

Python port of tools/build_windows.ps1. The PowerShell original requires
PowerShell 7 (`#Requires -Version 7.0`, `ProcessStartInfo.ArgumentList`), and this
machine only has Windows PowerShell 5.1, so the pipeline is expressed in Python and
runs through the `py` launcher.

Behaviour matches build_windows.ps1 stage-for-stage:
  * engine version and export-template version must be identical;
  * export runs with APPDATA redirected into the project so the user's real Godot
    editor settings are never touched;
  * a stage fails on non-zero exit or on SCRIPT ERROR/SHADER ERROR/ERROR/FAIL/WARNING
    lines (a small documented allowlist covers environment noise);
  * the final PCK is functionally smoke-tested with the same-version editor runtime
    (`--main-pack` + external fixture), and the real release EXE is launched
    separately for a normal-start check;
  * BUILD_INFO.json records which checks really ran;
  * the package directory is checked for unexpected files, then hashed and zipped.

Additions over the original:
  * `--install-templates TPZ` extracts the matching official template out of the
    official .tpz archive, so a clean machine needs one command;
  * `--clean` removes only this pipeline's own outputs, never a directory tree.

Usage:
    py tools/build_windows.py --install-templates D:\\game\\downloads\\Godot_v4.7.2-stable_export_templates.tpz
    py tools/build_windows.py                 # export + package + smoke + zip
    py tools/build_windows.py --pack-only     # PCK only (diagnostic)
    py tools/build_windows.py --skip-smoke --no-zip
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path

DEFAULT_GODOT = r"D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe"
# Hard build precondition: the editor and the export templates must both report this
# exact version, otherwise the engine refuses (or silently mis-packs) the export.
EXPECTED_ENGINE_VERSION = "4.7.2.stable.official.ed1daf0bf"
EXPECTED_ENGINE_PREFIX = "4.7.2.stable"
# Directory name Godot uses for template lookups: the version without its build hash.
TEMPLATE_VERSION_DIR = "4.7.2.stable"
PRESET_NAME = "Windows Desktop"
PACKAGE_NAME = "star_abyss_windows_x64"
ZIP_STEM = "star_abyss"
EXE_NAME = "StarAbyss.exe"
PCK_NAME = "StarAbyss.pck"
ALLOWED_PACKAGE_FILES = (
    "StarAbyss.exe", "StarAbyss.pck", "试玩说明.txt", "GODOT_LICENSE.txt",
    "THIRD_PARTY_NOTICES.json", "BUILD_INFO.json", "SHA256SUMS.txt",
)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GAME_PATH = PROJECT_ROOT / "godot"
DEFAULT_BUILD_ROOT = PROJECT_ROOT / "builds" / "windows"
DIAGNOSTICS_PATH = PROJECT_ROOT / ".local" / "export-diagnostics"
# Artefacts retired by --clean are moved here (timestamped) instead of being deleted, so a
# build that fails after cleaning can never leave the tree without a usable package.
PREVIOUS_BUILD_PATH = DIAGNOSTICS_PATH / "previous_build"

# Build invariant: NOTHING may be written outside the workspace (D:\game); this
# environment sandboxes the engine to that tree. Every user directory the engine would
# normally use is therefore redirected into .local/.
# APPDATA also decides where export templates are looked up, so redirecting it means the
# engine's native lookup <APPDATA>/Godot/export_templates/<version>/ points INSIDE the
# project: export_presets.cfg can leave custom_template/{debug,release} empty (no
# "res://../" path escape, no machine-specific absolute path) and the same script works
# unchanged on a normal machine that has templates in its real %APPDATA%.
APPDATA_PATH = PROJECT_ROOT / ".local" / "appdata"
LOCAL_APPDATA_PATH = PROJECT_ROOT / ".local" / "localappdata"
# The exporter serialises project.binary through the OS temp directory before adding it
# to the PCK. When that write fails the export still exits 0 but the pack ships an EMPTY
# project.binary and cannot start, so TEMP/TMP must be writable too.
TEMP_PATH = PROJECT_ROOT / ".local" / "temp"
ENGINE_ENV_OVERRIDES = {
    "APPDATA": str(APPDATA_PATH),
    "LOCALAPPDATA": str(LOCAL_APPDATA_PATH),
    "TEMP": str(TEMP_PATH),
    "TMP": str(TEMP_PATH),
}

TEMPLATE_DIR = APPDATA_PATH / "Godot" / "export_templates" / TEMPLATE_VERSION_DIR


def template_dir() -> Path:
    """Godot's own template directory as seen by the build (APPDATA is redirected)."""
    return TEMPLATE_DIR


def template_exe(kind: str = "release") -> Path:
    return template_dir() / f"windows_{kind}_x86_64.exe"


# Engine lines caused by this environment, never by the game or the export itself:
#   * the Windows certificate store is not readable here;
#   * the engine is not allowed to write its own editor settings/cache/help cache or
#     user:// logs outside the project in this sandbox, so the editor reports that it
#     could not save them (proved with .local/export-diagnostics/probe_*; reads of the
#     real %APPDATA%/Godot -- where export templates live -- work fine);
#   * "can't save resource to empty path" is the same editor-settings save path.
# Each pattern is deliberately narrow: it can only match editor user-directory noise,
# never an export-output or gameplay failure.
IGNORED_ERROR_PATTERNS = (
    r"Failed to read the root certificate store",
    r"Error saving editor settings to",
    r"Cannot save file '[^']*[\\/]AppData[\\/][^']*editor_settings",
    r"Cannot create file '[^']*[\\/]AppData[\\/][^']*editor_doc_cache",
    r"Cannot save editor help cache",
    r"Cannot create editor (data|config|cache) directory",
    r"Could not create directory: '[^']*[\\/]AppData[\\/]",
    r"Could not open 'user://' directory",
    r"Could not create directory: 'user://",
    r"Failed to open log file for writing: user://",
    r"Can't save resource to empty path",
)
IGNORED_ERRORS = tuple(re.compile(pattern) for pattern in IGNORED_ERROR_PATTERNS)

ERROR_PATTERN = re.compile(r"(?im)^\s*(SCRIPT ERROR:|SHADER ERROR:|ERROR:|FAIL:|WARNING:)")
SMOKE_MARKER = re.compile(r"EXPORT SMOKE RESULT: (\d+) checks, (\d+) failures")
AUDIT_MARKER = re.compile(r"PACK AUDIT RESULT: (\d+) checks, (\d+) failures")


class BuildError(RuntimeError):
    """A stage failed; the message is the summary printed before a non-zero exit."""


@dataclass(frozen=True)
class Paths:
    """Output locations for one build run."""

    build_root: Path
    package_path: Path
    exe: Path
    pck: Path
    zip: Path

    @property
    def zip_hash(self) -> Path:
        return Path(str(self.zip) + ".sha256")

    @classmethod
    def from_root(cls, root: Path, version: str = "") -> "Paths":
        package = root / PACKAGE_NAME
        # Version-tagged archive name so two releases can never be confused.
        tag = f"_{version}" if version else ""
        return cls(build_root=root, package_path=package,
                   exe=package / EXE_NAME, pck=package / PCK_NAME,
                   zip=root / f"{ZIP_STEM}{tag}_windows_x64.zip")


def log(message: str) -> None:
    print(message, flush=True)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def genuine_error_lines(text: str) -> list[str]:
    """Engine error/warning lines minus the documented environment noise."""
    problems: list[str] = []
    for line in text.splitlines():
        if not ERROR_PATTERN.match(line):
            continue
        stripped = line.strip()
        if any(ignored.search(stripped) for ignored in IGNORED_ERRORS):
            continue
        problems.append(stripped)
    return problems


def running_engine_processes() -> list[str]:
    """Return descriptions of other running engine processes (empty when exclusive)."""
    if os.name != "nt":
        return []
    try:
        listing = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True,
                                 text=True, encoding="utf-8", errors="replace",
                                 timeout=60).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        log(f"  note: could not list processes to check exclusivity ({exc})")
        return []
    busy: list[str] = []
    for line in listing.splitlines():
        fields = [field.strip('" ') for field in line.split('","')]
        if not fields or not fields[0]:
            continue
        name = fields[0].strip('"')
        if name.lower().startswith("godot") or name.lower().startswith("starabyss"):
            pid = fields[1] if len(fields) > 1 else "?"
            busy.append(f"{name} (pid {pid})")
    return busy


def assert_exclusive_project_access(wait_seconds: int = 0) -> None:
    """Refuse to build while another engine process holds the project.

    Concurrent access to the same project's `.godot` cache makes `--editor --import`
    crash with 3221225477 (0xC0000005 access violation); the export can then produce a
    pack with missing or half-imported resources.
    """
    deadline = time.time() + max(0, wait_seconds)
    busy = running_engine_processes()
    while busy and time.time() < deadline:
        log(f"  waiting for exclusive project access ({len(busy)} engine process(es) running)...")
        time.sleep(5)
        busy = running_engine_processes()
    if busy:
        raise BuildError(
            "Another engine process is using this project; a concurrent export can corrupt "
            "the .godot import cache (observed crash 0xC0000005). Waiting is supported with "
            "--wait-for-exclusive SECONDS. Running:\n  " + "\n  ".join(busy))
    log("Preflight: exclusive project access (no other engine process running)")


def run_stage(name: str, executable: Path, arguments: list[str],
              working_directory: Path | None = None,
              timeout: int = 120) -> str:
    """Run one engine stage; return combined stdout+stderr, raise BuildError on failure."""
    command = [str(executable), *arguments]
    engine_log_path = DIAGNOSTICS_PATH / f"{name}.log"
    # Every engine run gets user directories redirected into the project: this
    # environment forbids writes outside the workspace (proved by
    # .local/export-diagnostics/probe_write_scope.gd), and a real %TEMP% would silently
    # produce a PCK with an empty project.binary.
    env = dict(os.environ)
    env.update(ENGINE_ENV_OVERRIDES)
    for override in (APPDATA_PATH, LOCAL_APPDATA_PATH, TEMP_PATH):
        override.mkdir(parents=True, exist_ok=True)

    started = time.time()
    try:
        completed = subprocess.run(
            command, cwd=str(working_directory or GAME_PATH), env=env,
            capture_output=True, timeout=timeout, text=True,
            encoding="utf-8", errors="replace",
        )
        output = (completed.stdout or "") + (completed.stderr or "")
        code = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode("utf-8", "replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        output = stdout + stderr
        code = -1
        timed_out = True

    (DIAGNOSTICS_PATH / f"{name}.output.txt").write_text(output, encoding="utf-8")
    engine_log = ""
    if engine_log_path.exists():
        engine_log = engine_log_path.read_text(encoding="utf-8", errors="replace")

    problems = genuine_error_lines(output) + genuine_error_lines(engine_log)
    log(f"  [{name}] exit {code}, {time.time() - started:.1f}s")
    if timed_out:
        raise BuildError(f"{name} timed out after {timeout}s\n{output[-4000:]}")
    if code != 0:
        raise BuildError(f"{name} failed with exit code {code}\n{output[-4000:]}")
    if problems:
        summary = "\n".join(f"  ! {line}" for line in problems[:20])
        raise BuildError(f"{name} produced {len(problems)} error/warning line(s):\n{summary}")
    return output


def engine_version(godot: Path) -> str:
    output = run_stage("editor-version", godot, ["--version"], PROJECT_ROOT, 60)
    lines = [line.strip() for line in output.strip().splitlines() if line.strip()]
    if not lines:
        raise BuildError("Could not read the editor version from `--version` output.")
    return lines[-1]


def project_version() -> str:
    """Read application/config/version from the project; a release must carry one."""
    manifest = GAME_PATH / "project.godot"
    if not manifest.is_file():
        raise BuildError(f"Missing project manifest: {manifest}")
    text = manifest.read_text(encoding="utf-8", errors="replace")
    match = re.search(r'^config/version\s*=\s*"([^"]+)"', text, re.MULTILINE)
    if not match or not match.group(1).strip():
        raise BuildError(
            "project.godot has no application/config/version; a release package must "
            "carry a version number.")
    return match.group(1).strip()


def template_version_of(template: Path) -> str:
    """Ask the template binary for its engine version."""
    output = run_stage("template-version", template, ["--version"], PROJECT_ROOT, 60)
    lines = [line.strip() for line in output.strip().splitlines() if line.strip()]
    if not lines:
        raise BuildError(f"Could not read the template version from {template}")
    return lines[-1]


SOURCE_ROOTS = ("scripts", "scenes", "resources", "assets")
SOURCE_FILES = ("project.godot", "export_presets.cfg")


def check_scripts_parse(godot: Path) -> int:
    """Refuse to export a tree where any GDScript fails to parse.

    A pack built while someone is saving a script can be ship-shaped and still broken:
    the exported bytecode carries `Parse Error: Function "x()" not found in base self`
    and the game dies at load. `pack_audit.gd` cannot see that (it does not compile
    scripts), so this gate runs before anything is exported.
    """
    sources = sorted(GAME_PATH.glob("scripts/**/*.gd"))
    if not sources:
        raise BuildError("No GDScript sources found under godot/scripts.")
    log(f"Checking {len(sources)} scripts for parse errors before exporting...")
    for source in sources:
        relative = source.relative_to(GAME_PATH).as_posix()
        try:
            run_stage("script-parse", godot,
                      ["--headless", "--path", str(GAME_PATH), "--check-only",
                       "--script", f"res://{relative}"], GAME_PATH, 120)
        except BuildError as exc:
            raise BuildError(
                f"GDScript parse gate failed for {relative}; the project is mid-edit and "
                f"must not be exported:\n{exc}") from exc
    log(f"PASS: all {len(sources)} scripts parse cleanly")
    return len(sources)


def source_snapshot() -> dict[str, tuple[int, int]]:
    """Fingerprint of the shipped sources: (file count, newest mtime in ns)."""
    snapshot: dict[str, tuple[int, int]] = {}
    for root in SOURCE_ROOTS:
        base = GAME_PATH / root
        if not base.is_dir():
            continue
        files = 0
        newest = 0
        for path in base.rglob("*"):
            if path.is_file():
                files += 1
                newest = max(newest, path.stat().st_mtime_ns)
        snapshot[root] = (files, newest)
    for name in SOURCE_FILES:
        target = GAME_PATH / name
        if target.is_file():
            snapshot[name] = (1, target.stat().st_mtime_ns)
    return snapshot


def assert_sources_unchanged(before: dict[str, tuple[int, int]]) -> None:
    """A build made while somebody edits the tree is not a release candidate."""
    after = source_snapshot()
    changed = [
        f"{key}: {before.get(key)} -> {after.get(key)}"
        for key in sorted(set(before) | set(after))
        if before.get(key) != after.get(key)
    ]
    if changed:
        raise BuildError(
            "Project sources changed while the build was running, so this package is "
            "not a valid candidate (someone saved files during the export):\n  "
            + "\n  ".join(changed)
            + "\nRebuild once the tree is quiet.")
    log(f"PASS: source tree unchanged during the build ({len(after)} areas fingerprinted)")


def template_version_evidence() -> tuple[str, Path]:
    """Read the engine version from an installed export template.

    Two independent methods are used because the template is a GUI-subsystem binary:
    `--version` output is only visible when stdout is a pipe (interactively it is
    dropped), so the version string is ALSO located in the binary itself. If the two
    disagree the build stops. Failing to find any evidence is a build failure on purpose:
    a version check that silently passes would defeat pinning the exact engine build.
    """
    rejected: list[str] = []
    for kind in ("release", "debug"):
        candidate = template_exe(kind)
        if not candidate.is_file():
            continue
        reported = ""
        try:
            reported = template_version_of(candidate)
        except BuildError as exc:
            rejected.append(f"{candidate.name}: --version gave {str(exc).splitlines()[0]}")
        try:
            data = candidate.read_bytes()
        except OSError as exc:
            rejected.append(f"{candidate.name}: unreadable ({exc})")
            continue
        embedded = embedded_version(data)
        if reported and not re.match(r"^\d+\.\d+\.\d+\.", reported):
            rejected.append(f"{candidate.name}: unexpected --version output {reported!r}")
            continue
        # The embedded copy may omit the build hash ("4.7.2.stable.official"), so the two
        # are compared as prefixes rather than for equality.
        if reported and embedded and not (reported.startswith(embedded)
                                          or embedded.startswith(reported)):
            raise BuildError(
                f"Template {candidate.name} reports {reported} but embeds {embedded}.")
        if not reported and not embedded:
            rejected.append(f"{candidate.name}: no version evidence (--version and byte scan)")
            continue
        version = max((reported, embedded), key=len)
        # If the hash part is missing from the version string, require it in the bytes.
        expected_hash = EXPECTED_ENGINE_VERSION.split(".")[-1]
        if version != EXPECTED_ENGINE_VERSION:
            if data.find(expected_hash.encode("ascii")) < 0:
                raise BuildError(
                    f"Template {candidate.name} only yields {version!r} and does not contain "
                    f"the expected build hash {expected_hash!r}.")
            log(f"  build hash {expected_hash} found inside {candidate.name}; "
                f"version strings observed: --version={reported or '(empty pipe)'} "
                f"embedded={embedded or '(not found)'}")
            return EXPECTED_ENGINE_VERSION, candidate
        log(f"  version evidence from {candidate.name}: --version={reported or '(empty pipe)'} "
            f"embedded={embedded or '(not found)'}")
        return version, candidate
    detail = "\n  ".join(rejected) if rejected else "no template installed"
    raise BuildError(f"Could not establish the engine version of any installed template:\n  {detail}")


def embedded_version(data: bytes) -> str:
    """Locate the engine version string inside template binary bytes."""
    match = re.search(rb"(4\.\d+\.\d+\.stable\.official(?:\.[0-9a-f]{7,9})?)", data)
    return match.group(1).decode("ascii") if match else ""


def check_preset_pin(require_files: bool = True) -> None:
    """The preset must leave custom_template empty: the native template lookup is used.

    An empty pin makes Godot resolve <APPDATA>/Godot/export_templates/<version>/, which
    the build redirects into the project. A non-empty pin is rejected because it pins a
    machine-specific or path-escaping location that would not reproduce elsewhere.
    """
    preset = GAME_PATH / "export_presets.cfg"
    if not preset.is_file():
        raise BuildError(f"Missing export preset file: {preset}")
    text = preset.read_text(encoding="utf-8", errors="replace")
    if f'name="{PRESET_NAME}"' not in text:
        raise BuildError(f'export_presets.cfg has no preset named "{PRESET_NAME}"')
    for key in ("custom_template/debug", "custom_template/release"):
        match = re.search(rf'^{re.escape(key)}\s*=\s*"(.*)"\s*$', text, re.MULTILINE)
        value = (match.group(1) if match else "").strip()
        if not value:
            log(f"Preset {key}: empty -> native lookup {template_dir()}")
            continue
        message = (f"Preset {key} pins {value!r}. Leave it empty so Godot uses the native "
                   f"lookup {template_dir()}; a pinned path does not reproduce.")
        if require_files:
            raise BuildError(message)
        log(f"  note: {message} (allowed for --pack-only)")


def resolve_template() -> Path:
    """Return the release template this machine will use, or raise BuildError."""
    candidate = template_exe()
    if candidate.is_file():
        return candidate
    raise BuildError(
        "Missing Godot 4.7.2 release export template. Expected:\n"
        f"  {candidate}\n"
        "Install it with (this script never downloads anything):\n"
        "  py tools/build_windows.py --install-templates <Godot_v4.7.2-stable_export_templates.tpz>\n"
        "See docs/BUILD_WINDOWS.md."
    )


def install_templates(archive: Path, force: bool = False) -> None:
    """Extract windows_release_x86_64.exe from an official .tpz archive."""
    archive = archive.resolve()
    if not archive.is_file():
        raise BuildError(f"Export-template archive not found: {archive}")
    size = archive.stat().st_size
    if size < 1 << 20:
        raise BuildError(f"Export-template archive looks truncated: {archive} is {size} bytes")
    log(f"Installing export templates from {archive} ({size:,} bytes)")
    log(f"  archive sha256: {sha256_of(archive)}")
    target_exe = template_exe("release")
    try:
        with zipfile.ZipFile(archive) as bundle:
            bad_member = bundle.testzip()
            if bad_member:
                raise BuildError(f"Export-template archive is corrupt at member {bad_member}")
            available = [name for name in bundle.namelist() if name.startswith("templates/")]
            log(f"  archive top-level entries: {len(available)} in templates/")
            # Godot validates debug *and* release templates for this preset even on a
            # release-only export, so both Windows x64 binaries are installed.
            for kind in ("release", "debug"):
                suffix = f"windows_{kind}_x86_64.exe"
                wanted = [name for name in available if name.endswith(suffix)]
                if not wanted:
                    raise BuildError(f"Archive contains no templates/{suffix}")
                member = wanted[0]
                destination = template_exe(kind)
                destination.parent.mkdir(parents=True, exist_ok=True)
                if destination.exists() and not force:
                    log(f"  already installed: {destination}")
                else:
                    with bundle.open(member) as source, destination.open("wb") as target:
                        shutil.copyfileobj(source, target, 1 << 20)
                    log(f"  extracted {member} -> {destination}")
                log(f"  {suffix}: {destination.stat().st_size:,} bytes  "
                    f"sha256 {sha256_of(destination)}")
    except zipfile.BadZipFile as exc:
        raise BuildError(f"Export-template archive is not a readable zip: {exc}") from exc

    # Hard requirement: the template must be the exact build this editor expects.
    version, reporting = template_version_evidence()
    log(f"  template version: {version} (reported by {reporting.name})")
    if version != EXPECTED_ENGINE_VERSION:
        raise BuildError(
            f"Template version {version} does not match the required engine build "
            f"{EXPECTED_ENGINE_VERSION}.")
    log("PASS: template installed into the engine's own template directory "
        f"({template_dir()}); custom_template stays empty in export_presets.cfg")


def run_pack_audit(godot: Path, paths: Paths) -> int:
    """Second gate: audited content of the finished pack by tools/pack_audit.gd.

    Asserts every shipped audio cue exists and decodes, every scene and GLB is present,
    no development test leaked in, and `application/run/main_scene` survived the export.
    """
    audit_script = PROJECT_ROOT / "tools" / "pack_audit.gd"
    if not audit_script.is_file():
        raise BuildError(f"Missing pack audit script: {audit_script}")
    output = run_stage(
        "pack-audit", godot,
        ["--headless", "--main-pack", str(paths.pck), "--script", str(audit_script),
         "--audio-driver", "Dummy",
         "--log-file", str(DIAGNOSTICS_PATH / "pack-audit.log")],
        paths.package_path, 600,
    )
    match = AUDIT_MARKER.search(output)
    if not match:
        raise BuildError("Pack audit did not produce its result marker.")
    checks, failures = int(match.group(1)), int(match.group(2))
    if failures:
        raise BuildError(f"Pack audit reported {failures} failure(s) of {checks} checks.")
    log(f"PASS: pack audit {checks} checks, 0 failures "
        "(assets, scenes, models, no test leakage, main scene intact)")
    return checks


def assert_pck_is_launchable(pck: Path) -> int:
    """A launchable Godot pack must contain a non-empty project.binary entry.

    The exporter writes project.binary through the OS temp directory; when that write
    fails the PCK is still produced (exit code 0) but the entry is 0 bytes and the pack
    cannot start. This check turns that silent failure into a build failure.
    """
    import inspect_pck  # sibling module in tools/

    try:
        entries, info = inspect_pck.read_index(pck)
    except SystemExit as exc:
        raise BuildError(f"PCK index is unreadable: {exc}") from exc
    sizes = {path.removeprefix("res://"): size for path, _offset, size in entries}
    if "project.binary" not in sizes:
        raise BuildError("PCK has no project.binary entry; the pack cannot launch.")
    if sizes["project.binary"] == 0:
        raise BuildError(
            "PCK contains an EMPTY project.binary (0 bytes): the exporter could not write "
            "its temporary file (see the %TEMP% redirection in run_stage). "
            "The pack is not launchable.")
    log(f"  PCK index: {len(entries)} files, index at {info['directory_offset']:,}, "
        f"project.binary {sizes['project.binary']:,} bytes")
    return len(entries)


def clean_outputs(paths: Paths) -> None:
    """Retire the previous artefacts into .local/previous_build/<stamp> instead of deleting.

    Only files this pipeline owns are touched, one by one; no directory tree is ever
    removed and unknown files are left alone (verify_package_contents() then fails loudly
    rather than silently deleting somebody else's file).

    Moving instead of deleting is deliberate: this was learned the hard way when
    "--clean then a build that fails during preflight" emptied builds/ and destroyed the
    only copy of a package others were still testing.
    """
    owned = [paths.exe, paths.pck, paths.zip, paths.zip_hash,
             paths.package_path / "试玩说明.txt",
             paths.package_path / "GODOT_LICENSE.txt",
             paths.package_path / "THIRD_PARTY_NOTICES.json",
             paths.package_path / "BUILD_INFO.json",
             paths.package_path / "SHA256SUMS.txt"]
    archive = PREVIOUS_BUILD_PATH / time.strftime("%Y%m%d-%H%M%S")
    retired = 0
    for path in owned:
        if path.is_file():
            archive.mkdir(parents=True, exist_ok=True)
            path.replace(archive / path.name)
            retired += 1
            log(f"  retired {path}")
    if retired:
        log(f"  {retired} file(s) kept in {archive} (a failed build never destroys them)")


def write_engine_notices(godot: Path, paths: Paths) -> None:
    """Read licence notices from the engine itself instead of hard-coding them."""
    script = DIAGNOSTICS_PATH / "write_engine_notices.gd"
    script.write_text(
        """extends SceneTree

func _initialize() -> void:
\tvar destination: String = OS.get_cmdline_user_args()[0]
\tvar license_file: FileAccess = FileAccess.open(destination.path_join("GODOT_LICENSE.txt"), FileAccess.WRITE)
\tif license_file == null:
\t\tpush_error("Cannot write Godot license notice")
\t\tquit(1)
\t\treturn
\tlicense_file.store_string(Engine.get_license_text())
\tlicense_file.close()
\tvar third_party: FileAccess = FileAccess.open(destination.path_join("THIRD_PARTY_NOTICES.json"), FileAccess.WRITE)
\tif third_party == null:
\t\tpush_error("Cannot write third-party notices")
\t\tquit(1)
\t\treturn
\tthird_party.store_string(JSON.stringify({"copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\\t"))
\tthird_party.close()
\tquit(0)
""",
        encoding="utf-8",
    )
    run_stage("engine-notices", godot,
              ["--headless", "--path", str(GAME_PATH), "--script", str(script),
               "--", str(paths.package_path)],
              GAME_PATH, 120)


PACKAGE_README = """星渊遗迹 / Star Abyss — Windows x64 试玩包

启动：完整解压后双击 StarAbyss.exe。请将 StarAbyss.pck 保持在同一目录。
本包无需安装 Godot 或 Blender。使用支持 Vulkan 的 Windows x64 PC。

WASD 移动；鼠标转镜头；左键三段剑击；E 星刃斩；Shift 闪避；Space 跳跃；Esc 暂停。
从主菜单进入两间普通房与第三间 Boss 房。普通房清场后必须选择祝福，再穿过北侧出口。
暂停、胜利和失败界面可重新开始或返回主菜单；重新开始会清空本局进度。

首次游玩请确认游戏音量与预警可读性，完整走完一局后分别尝试重开和返回主菜单。
自动化检查不能代替人工的手感、画面和音效评价。

引擎许可见 GODOT_LICENSE.txt；引擎第三方组件通知见 THIRD_PARTY_NOTICES.json。
SHA256SUMS.txt 可用于核对解压后的文件完整性。
"""


def verify_package_contents(paths: Paths) -> None:
    unexpected = [path.name for path in paths.package_path.iterdir()
                  if path.is_file() and path.name not in ALLOWED_PACKAGE_FILES]
    if unexpected:
        raise BuildError(
            "Unexpected files in package directory; inspect without deleting user files: "
            + ", ".join(sorted(unexpected)))


def run_smoke(godot: Path, paths: Paths) -> dict:
    """Validate the final PCK and the real release binary.

    Returns the two independent verification results separately: loading the pack with
    the editor runtime does NOT prove that the release binary starts, so the two flags
    must never share a source.

    Both stages run with the working directory set to the package directory and launch
    the exported artefacts by absolute path, so nothing can fall back to the source
    project under godot/.
    """
    # Official release templates disable --main-pack / --script overrides, so the
    # final data pack is validated with the identical-version editor runtime, and
    # the real release binary is launched separately for a normal-start check.
    smoke_script = GAME_PATH / "tests" / "export_smoke_test.gd"
    screenshot = DIAGNOSTICS_PATH / "package_gameplay.png"
    output = run_stage(
        "pck-functional-smoke", godot,
        ["--main-pack", str(paths.pck), "--fixed-fps", "60", "--max-fps", "0",
         "--disable-vsync", "--audio-driver", "Dummy", "--script", str(smoke_script),
         "--log-file", str(DIAGNOSTICS_PATH / "pck-functional-smoke.log"),
         "--", str(screenshot)],
        paths.package_path, 600,
    )
    match = SMOKE_MARKER.search(output)
    if not match:
        raise BuildError("Release smoke did not produce its success marker.")
    checks, failures = int(match.group(1)), int(match.group(2))
    if failures:
        raise BuildError(f"Release smoke reported {failures} failure(s) of {checks} checks.")
    log(f"PASS: final PCK functional smoke under same-version editor runtime "
        f"({checks} checks, 0 failures)")

    start_output = run_stage(
        "release-normal-start", paths.exe,
        ["--fixed-fps", "60", "--audio-driver", "Dummy", "--quit-after", "120",
         "--log-file", str(DIAGNOSTICS_PATH / "release-normal-start.log")],
        paths.package_path, 180,
    )
    log(f"    cwd: {paths.package_path}   exe: {paths.exe}   (no --path, so the shipped "
        f"pck next to the exe is what runs)")
    # The release binary is a GUI-subsystem executable: its stdout is only reliable when
    # it is a pipe, so the engine log file is checked as evidence as well.
    start_log = DIAGNOSTICS_PATH / "release-normal-start.log"
    evidence = start_output
    if start_log.is_file():
        evidence += "\n" + start_log.read_text(encoding="utf-8", errors="replace")
    highlights = [line.strip() for line in evidence.splitlines()
                  if re.search(r"(?i)Vulkan|Forward\+|OpenGL|Godot Engine v|Using Device", line)]
    for line in dict.fromkeys(highlights):
        log(f"    {line}")
    if "Forward+" not in evidence:
        raise BuildError(
            "Release EXE did not report a Forward+ renderer in its startup output or log. "
            "The build must not be shipped as a verified Forward+ build.")
    log("PASS: real release EXE normal startup (separate from PCK functional smoke)")
    return {
        "pck_smoke_checks": checks,
        "pck_smoke_verified": True,
        "normal_start_verified": True,
        "start_cwd": str(paths.package_path),
        "start_exe": str(paths.exe),
    }


def verify_package(target: Path, godot: Path) -> int:
    """Clean-room check: unpack a built package into a fresh directory and start it there.

    This is what a player does, so it is a separate gate from the build: the artefact is
    extracted somewhere new (never reusing the build directory), file hashes are compared
    against SHA256SUMS.txt, and the executable is launched with its working directory set
    to the extraction root -- with no --path override, so only the shipped data can load.
    """
    target = target.resolve()
    if not target.exists():
        raise BuildError(f"Nothing to verify at {target}")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    room = DIAGNOSTICS_PATH / "cleanroom" / stamp
    room.mkdir(parents=True, exist_ok=True)
    log(f"Clean-room directory: {room}")

    if target.is_dir():
        shutil.copytree(target, room, dirs_exist_ok=True)
        source_description = f"directory {target}"
    else:
        try:
            with zipfile.ZipFile(target) as bundle:
                bad_member = bundle.testzip()
                if bad_member:
                    raise BuildError(f"Release archive is corrupt at member {bad_member}")
                names = bundle.namelist()
                bundle.extractall(room)
        except zipfile.BadZipFile as exc:
            raise BuildError(f"Release archive is not a readable zip: {exc}") from exc
        source_description = f"zip {target} ({len(names)} entries)"
        log(f"  extracted {len(names)} entries")
        for name in names:
            if os.path.basename(name) == "StarAbyss.pck" and not name.startswith(
                    os.path.basename(os.path.dirname(name)) + "/"):
                raise BuildError(
                    f"Archive member {name} would unpack outside its own folder; refusing.")

    log(f"  source: {source_description}")
    # The exe sits either at the room root or inside a single package folder.
    candidates = sorted(room.rglob(EXE_NAME))
    if not candidates:
        raise BuildError(f"Package contains no {EXE_NAME}")
    if len(candidates) > 1:
        raise BuildError(f"Package contains {len(candidates)} copies of {EXE_NAME}: "
                         + ", ".join(str(path) for path in candidates))
    exe = candidates[0]
    pack = exe.with_suffix(".pck")
    if not pack.is_file():
        raise BuildError(f"{EXE_NAME} has no {pack.name} next to it; the package cannot run.")

    # Verify the shipped hashes rather than trusting the copy.
    sums = exe.parent / "SHA256SUMS.txt"
    checked = 0
    if sums.is_file():
        for line in sums.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            expected, _, name = line.partition("  ")
            candidate = exe.parent / name.strip()
            if not candidate.is_file():
                raise BuildError(f"SHA256SUMS.txt lists {name!r} but the package lacks it.")
            actual = sha256_of(candidate)
            if actual != expected.strip().lower():
                raise BuildError(
                    f"Hash mismatch for {name}: SHA256SUMS.txt says {expected.strip()} "
                    f"but the file is {actual}")
            checked += 1
        log(f"PASS: {checked} file hash(es) match SHA256SUMS.txt")
    else:
        log("  note: package has no SHA256SUMS.txt; hashes are not cross-checked here")

    log(f"  exe: {exe} ({exe.stat().st_size:,} bytes)")
    log(f"  pck: {pack} ({pack.stat().st_size:,} bytes)  sha256 {sha256_of(pack)}")
    log(f"  launching with cwd = {exe.parent}")

    env_backup = {name: os.environ.get(name) for name in ENGINE_ENV_OVERRIDES}
    os.environ.update(ENGINE_ENV_OVERRIDES)
    try:
        log_path = DIAGNOSTICS_PATH / "cleanroom-start.log"
        completed = subprocess.run(
            [str(exe), "--quit-after", "120", "--audio-driver", "Dummy",
             "--log-file", str(log_path)],
            cwd=exe.parent, env=os.environ.copy(), capture_output=True, text=True, timeout=180)
    finally:
        for name, value in env_backup.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
    if completed.returncode != 0:
        raise BuildError(f"Clean-room launch exited with {completed.returncode}")
    evidence = (completed.stdout or "") + (completed.stderr or "")
    if log_path.is_file():
        evidence += "\n" + log_path.read_text(encoding="utf-8", errors="replace")
    if re.search(r"(?m)^\s*(SCRIPT ERROR|SHADER ERROR|Parse Error)", evidence):
        raise BuildError("Clean-room launch reported script/shader errors.")
    if "Forward+" not in evidence:
        raise BuildError("Clean-room launch did not report the Forward+ renderer.")
    for line in dict.fromkeys(
            item.strip() for item in evidence.splitlines()
            if re.search(r"(?i)Vulkan|Forward\+|Godot Engine v|Using Device", item)):
        log(f"    {line}")
    stray = [path.name for path in exe.parent.iterdir()
             if path.is_file() and path.name not in
             {EXE_NAME, PCK_NAME, "试玩说明.txt", "GODOT_LICENSE.txt",
              "THIRD_PARTY_NOTICES.json", "BUILD_INFO.json", "SHA256SUMS.txt"}]
    if stray:
        log(f"  note: the run created files next to the exe: {', '.join(sorted(stray))}")
    log(f"PASS: clean-room launch from {exe.parent} (exit 0, Forward+, no script errors)")
    return 0


def write_package_hashes(paths: Paths) -> None:
    """Recompute SHA256SUMS.txt over everything in the package directory."""
    hash_lines = [f"{sha256_of(path)}  {path.name}"
                  for path in sorted(paths.package_path.iterdir(), key=lambda item: item.name)
                  if path.is_file() and path.name != "SHA256SUMS.txt"]
    (paths.package_path / "SHA256SUMS.txt").write_text(
        "\n".join(hash_lines) + "\n", encoding="utf-8")


def write_release_zip(paths: Paths) -> None:
    """Rebuild the distributable zip and its .sha256 sidecar from the package directory."""
    if paths.zip.exists():
        paths.zip.unlink()
    with zipfile.ZipFile(paths.zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(paths.package_path.iterdir()):
            if path.is_file():
                bundle.write(path, f"{PACKAGE_NAME}/{path.name}")
    zip_hash = sha256_of(paths.zip)
    paths.zip_hash.write_text(f"{zip_hash}  {paths.zip.name}\n", encoding="utf-8")
    log(f"PASS: release package {paths.zip} ({paths.zip.stat().st_size:,} bytes)")
    log(f"SHA256: {zip_hash}")


def attest_native_input(paths: Paths, evidence: str, verified_by: str) -> int:
    """Record a completed verification of the shipped artefacts in BUILD_INFO.json.

    The build itself cannot know whether a human or an external harness exercised the
    package, so it writes `false` and this command is the only way to record the truth
    afterwards. It refuses to attest a package that is not a release candidate, never
    touches StarAbyss.exe / StarAbyss.pck, and regenerates the hashes and the zip.
    """
    info_path = paths.package_path / "BUILD_INFO.json"
    if not info_path.is_file():
        raise BuildError(f"No BUILD_INFO.json in {paths.package_path}; build the package first.")
    if not evidence.strip():
        raise BuildError("--evidence must describe the actual verification performed.")
    info = json.loads(info_path.read_text(encoding="utf-8"))
    if not info.get("release_candidate_eligible"):
        raise BuildError(
            "Refusing to attest a package whose release_candidate_eligible is not true.")
    before = {"exe": sha256_of(paths.exe), "pck": sha256_of(paths.pck)}
    # Attestation must describe THE package that was actually built, so the artefacts are
    # checked against the hashes recorded by that build before anything is written.
    for field, kind, path in (("exe_sha256", "exe", paths.exe),
                              ("pck_sha256", "pck", paths.pck)):
        recorded = (info.get(field) or "").strip().lower()
        if not recorded:
            raise BuildError(f"BUILD_INFO.json has no {field}; cannot tie the attestation "
                             "to a specific build.")
        if recorded != before[kind]:
            raise BuildError(
                f"{path.name} is {before[kind]} but BUILD_INFO.json records {field} "
                f"{recorded}: these artefacts are not the ones that were built and "
                "verified. Rebuild instead of attesting.")
    log(f"  artefacts match the built package: exe {before['exe'][:12]}…, pck {before['pck'][:12]}…")
    info["release_native_input_verified"] = True
    info["release_native_input_evidence"] = evidence.strip()
    info["human_playtest_verified"] = False
    info["human_playtest_note"] = "无人工试玩记录；L4 为 OS 级注入输入的机械佐证，不等同人工验收"
    info["verified_at_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    info["verified_by"] = verified_by
    info_path.write_text(json.dumps(info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    log(f"Attested native-input verification in {info_path}")
    log(f"  verified_by: {verified_by}")
    log(f"  verified_at_utc: {info['verified_at_utc']}")
    log("  human_playtest_verified: false (unchanged on purpose)")

    write_package_hashes(paths)
    log(f"  SHA256SUMS.txt regenerated ({len(info)} BUILD_INFO fields)")
    write_release_zip(paths)
    after = {"exe": sha256_of(paths.exe), "pck": sha256_of(paths.pck)}
    if before != after:
        raise BuildError(
            "Attestation changed StarAbyss.exe/pck, which must never happen: "
            f"{before} -> {after}")
    log("PASS: exe and pck are byte-identical to before the attestation")
    log("  Next: py tools\\build_windows.py --verify-package "
        f"{paths.zip}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Star Abyss Windows x64 release build")
    parser.add_argument("--godot", default=os.environ.get("STARABYSS_GODOT", DEFAULT_GODOT),
                        help="Path to the Godot 4.7.2 console editor binary")
    parser.add_argument("--out", default=str(DEFAULT_BUILD_ROOT),
                        help="Build output root (default: builds/windows)")
    parser.add_argument("--install-templates", default="", metavar="TPZ",
                        help="Extract the release template from an official .tpz archive and exit")
    parser.add_argument("--verify-package", default="", metavar="ZIP_OR_DIR",
                        help="Unpack a built package into a fresh directory, launch it from "
                             "there and report the result (clean-room verification)")
    parser.add_argument("--attest-native-input", action="store_true",
                        help="Record a completed native-input verification in the built "
                             "package's BUILD_INFO.json, then rebuild hashes and the zip")
    parser.add_argument("--evidence", default="", metavar="TEXT",
                        help="What was actually verified, for BUILD_INFO.json (required by "
                             "--attest-native-input)")
    parser.add_argument("--verified-by", default="", metavar="WHO",
                        help="Who verified it, for BUILD_INFO.json")
    parser.add_argument("--force-templates", action="store_true",
                        help="Re-extract the template even if one is already installed")
    parser.add_argument("--clean", action="store_true",
                        help="Retire previous outputs of this pipeline before building "
                             "(moved to .local/export-diagnostics/previous_build/<stamp>, "
                             "never deleted)")
    parser.add_argument("--pack-only", action="store_true", help="Export only the PCK (diagnostic)")
    parser.add_argument("--skip-smoke", action="store_true",
                        help="Skip gameplay/startup smoke checks (the build stays unverified)")
    parser.add_argument("--no-zip", action="store_true", help="Do not produce the distributable zip")
    parser.add_argument("--wait-for-exclusive", type=int, default=0, metavar="SECONDS",
                        help="Wait up to SECONDS for other engine processes to exit")
    args = parser.parse_args()

    godot = Path(args.godot).resolve()

    DIAGNOSTICS_PATH.mkdir(parents=True, exist_ok=True)

    try:
        if args.install_templates:
            install_templates(Path(args.install_templates), args.force_templates)
            log("PASS: export template installed")
            return 0

        if args.verify_package:
            # Needs no editor: it launches the shipped executable, exactly like a player.
            return verify_package(Path(args.verify_package), godot)

        if args.attest_native_input:
            version_tag = project_version()
            paths = Paths.from_root(Path(args.out).resolve(), version_tag)
            return attest_native_input(paths, args.evidence, args.verified_by or "unspecified")

        if not godot.is_file():
            log(f"FATAL: Godot editor not found: {godot}")
            return 2

        # The release archive must carry the project's own version, never a hard-coded one.
        version_tag = project_version()
        paths = Paths.from_root(Path(args.out).resolve(), version_tag)

        template = None if args.pack_only else resolve_template()

        log(f"Godot:    {godot}")
        log(f"Project:  {GAME_PATH}")
        log(f"Template: {template if template else '(pack-only, not used)'}")
        for name, value in ENGINE_ENV_OVERRIDES.items():
            log(f"Env {name:<12} = {value}")

        # ---- preflight: everything that can be checked without exporting happens first,
        # ---- so a failure here leaves the previous package completely untouched.
        assert_exclusive_project_access(args.wait_for_exclusive)
        check_preset_pin(require_files=not args.pack_only)

        version = engine_version(godot)
        log(f"Editor version: {version}")
        if version != EXPECTED_ENGINE_VERSION:
            raise BuildError(
                f"Editor version {version} does not match the required build "
                f"{EXPECTED_ENGINE_VERSION}; refusing to build a release package with a "
                "different engine.")

        template_sha = ""
        if template is not None:
            template_sha = sha256_of(template)
            log(f"Template sha256: {template_sha}")
            template_version, reporting = template_version_evidence()
            log(f"Template version: {template_version} (evidence from {reporting.name})")
            if template_version != version:
                raise BuildError(
                    f"Template/editor versions differ: template {template_version} versus "
                    f"editor {version}. Install the export templates that match the editor "
                    "exactly.")

        log("")
        log("=== DO NOT SAVE ANY PROJECT FILE WHILE THIS BUILD RUNS ===")
        log("Exporting a tree that is being edited ships broken script bytecode; the")
        log("parse gate and the source fingerprint below both guard against it.")
        log("")
        check_scripts_parse(godot)
        sources_before = source_snapshot()

        # Only now, with every preflight check green, are the previous artefacts retired.
        paths.build_root.mkdir(parents=True, exist_ok=True)
        paths.package_path.mkdir(parents=True, exist_ok=True)
        if args.clean:
            log("Retiring previous outputs of this pipeline")
            clean_outputs(paths)

        export_arguments = ["--headless", "--path", str(GAME_PATH),
                            "--log-file", str(DIAGNOSTICS_PATH / "export.log")]
        if args.pack_only:
            export_arguments += ["--export-pack", PRESET_NAME, str(paths.pck)]
        else:
            export_arguments += ["--export-release", PRESET_NAME, str(paths.exe)]
        log("Exporting...")
        export_output = run_stage("export", godot, export_arguments, GAME_PATH, 900)
        for line in export_output.splitlines():
            if re.search(r"(?i)export|\.pck|savepack", line):
                log(f"    {line.strip()}")

        if not paths.pck.is_file():
            raise BuildError("Export did not produce a PCK.")
        log(f"PASS: PCK exported ({paths.pck.stat().st_size:,} bytes)")
        # Gate 1 (fast, no engine): the pack index must hold a non-empty project.binary.
        assert_pck_is_launchable(paths.pck)
        # Gate 2 (audited content): every shipped asset present, no test leakage.
        audit_checks = run_pack_audit(godot, paths)
        if args.pack_only:
            log(f"SHA256 {sha256_of(paths.pck)}  {PCK_NAME}")
            return 0
        if not paths.exe.is_file():
            raise BuildError("Export did not produce a release executable.")
        log(f"PASS: EXE exported ({paths.exe.stat().st_size:,} bytes)")

        write_engine_notices(godot, paths)
        (paths.package_path / "试玩说明.txt").write_text(PACKAGE_README, encoding="utf-8")

        smoke = {"pck_smoke_checks": 0, "pck_smoke_verified": False,
                 "normal_start_verified": False, "start_cwd": "", "start_exe": ""}
        if args.skip_smoke:
            log("SKIP: gameplay/startup smoke.")
            log("WARNING: without the smoke fixture this package is NOT a release "
                "candidate; BUILD_INFO.json records that explicitly.")
        else:
            smoke = run_smoke(godot, paths)

        # Gate 3: nobody may have saved a project file while the pack was being made.
        assert_sources_unchanged(sources_before)

        release_candidate_eligible = (
            smoke["pck_smoke_verified"]
            and smoke["normal_start_verified"]
            and audit_checks > 0
        )

        build_info = {
            "stage": "P7",
            "version": version_tag,
            "target": "Windows x86_64",
            "configuration": "release",
            "engine_version": version,
            "built_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "template_path": str(template),
            "template_sha256": template_sha,
            "exe_bytes": paths.exe.stat().st_size,
            "pck_bytes": paths.pck.stat().st_size,
            "exe_sha256": sha256_of(paths.exe),
            "pck_sha256": sha256_of(paths.pck),
            "pack_audit_checks": audit_checks,
            "pack_audit_verified": True,
            "source_tree_stable_during_build": True,
            # Two independent facts: the pack loads under the editor runtime, and the
            # real release binary starts on its own. Neither implies the other.
            "pck_functional_smoke_checks": smoke["pck_smoke_checks"],
            "pck_functional_smoke_verified": smoke["pck_smoke_verified"],
            "release_normal_start_verified": smoke["normal_start_verified"],
            # Evidence trail for the launch check: the working directory and the exact
            # executable, so "it started the shipped build, not the source project" is
            # auditable from this file alone.
            "release_start_cwd": smoke["start_cwd"],
            "release_start_exe": smoke["start_exe"],
            "release_native_input_verified": False,
            "human_playtest_verified": False,
            "release_candidate_eligible": release_candidate_eligible,
        }
        (paths.package_path / "BUILD_INFO.json").write_text(
            json.dumps(build_info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        verify_package_contents(paths)

        write_package_hashes(paths)

        if args.no_zip:
            log("SKIP: zip archive (--no-zip)")
        else:
            write_release_zip(paths)

        log("")
        log(f"Output directory: {paths.package_path}")
        for path in sorted(paths.package_path.iterdir()):
            if path.is_file():
                log(f"  {path.name:<24}{path.stat().st_size:>14,} bytes")
        return 0
    except BuildError as exc:
        log("")
        log(f"FAIL: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
