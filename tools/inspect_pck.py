"""Inspect a Godot 4 PCK: file count, payload, and whether key files are present.

Godot 4.4+ writes the file index at the END of the pack and stores its offset in the
header, so the directory offset is read from the header instead of being assumed.
Reads the index instead of grepping bytes, so the report can be trusted.

Usage: py tools/inspect_pck.py <file.pck> [name-to-check ...]
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

MAGIC = 0x43504447  # "GDPC"


def parse_entries(raw: bytes, offset: int) -> tuple[list[tuple[str, int, int]], int]:
    (file_count,) = struct.unpack_from("<I", raw, offset)
    offset += 4
    entries: list[tuple[str, int, int]] = []
    for _ in range(file_count):
        (path_length,) = struct.unpack_from("<I", raw, offset)
        offset += 4
        path = raw[offset:offset + path_length].split(b"\x00", 1)[0].decode("utf-8", "replace")
        offset += path_length
        (file_offset, size) = struct.unpack_from("<QQ", raw, offset)
        offset += 16
        offset += 16  # md5
        offset += 4  # per-file flags
        entries.append((path, file_offset, size))
    return entries, offset


def plausible_path(path: str) -> bool:
    """Packs built with PACK_RELATIVE_PATHS store paths without a res:// prefix."""
    if not path or len(path) > 400:
        return False
    if any(ord(character) < 0x20 for character in path):
        return False
    return path.startswith("res://") or "/" in path or "." in path


def read_index(pck: Path) -> tuple[list[tuple[str, int, int]], dict]:
    raw = pck.read_bytes()
    magic, pack_version, major, minor, patch, flags = struct.unpack_from("<IIIIII", raw, 0)
    if magic != MAGIC:
        raise SystemExit(f"not a Godot PCK (magic {magic:#x})")
    (file_base,) = struct.unpack_from("<Q", raw, 24)
    (directory_offset,) = struct.unpack_from("<Q", raw, 32)

    # Godot 4.4+ puts the index at the end; the header stores where it starts.
    # Accept a candidate only if it parses cleanly AND ends exactly at end-of-file.
    candidates = [directory_offset] if 32 < directory_offset < len(raw) else []
    candidates.append(96)
    for offset in candidates:
        try:
            entries, end = parse_entries(raw, offset)
        except struct.error:
            continue
        if not entries or end != len(raw):
            continue
        if not all(plausible_path(path) for path, _o, _s in entries):
            continue
        info = {
            "pack_version": pack_version,
            "engine": f"{major}.{minor}.{patch}",
            "flags": flags,
            "file_base": file_base,
            "directory_offset": offset,
            "bytes": len(raw),
        }
        return entries, info
    raise SystemExit("could not locate a valid PCK file index")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: py tools/inspect_pck.py <file.pck> [name ...]", file=sys.stderr)
        return 2
    pck = Path(sys.argv[1])
    if not pck.is_file():
        print(f"FAIL: no such pck: {pck}", file=sys.stderr)
        return 2
    entries, info = read_index(pck)
    payload = sum(size for _name, _offset, size in entries)
    print(f"pck: {pck}")
    print(f"size: {info['bytes']:,} bytes")
    print(f"engine: {info['engine']}  pack_version: {info['pack_version']}  "
          f"flags: {info['flags']}  file_base: {info['file_base']}")
    print(f"index at: {info['directory_offset']:,}  files: {len(entries)}  "
          f"payload: {payload:,} bytes")
    missing = 0
    for wanted in sys.argv[2:]:
        hits = [entry for entry in entries if entry[0].endswith(wanted)]
        if hits:
            for path, _offset, size in hits:
                print(f"PRESENT {wanted:<22} {size:>10,} bytes  {path}")
        else:
            print(f"MISSING {wanted}")
            missing += 1
    print("largest entries:")
    for path, _offset, size in sorted(entries, key=lambda item: item[2], reverse=True)[:8]:
        print(f"  {size:>10,}  {path}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
