#!/usr/bin/env python3
"""Non-installing, bounded ZIP preflight for developer-supplied avatar packages.

This is NOT a Cubism renderer, extractor, permission grant, signature check,
or proof that a character asset is licensed for redistribution.
"""

from __future__ import annotations

import argparse
import json
import re
import stat
import zipfile
from pathlib import Path
from typing import BinaryIO

MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_ENTRIES = 512
MAX_TOTAL_BYTES = 128 * 1024 * 1024
MAX_FILE_BYTES = 32 * 1024 * 1024
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_RATIO = 100
_SEGMENT = re.compile(r"^[A-Za-z0-9_-][A-Za-z0-9_.-]*$")
_PACKAGE_ID = re.compile(r"^[a-z][a-z0-9_-]{2,63}$")
_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


class UnsafeAvatarArchive(ValueError):
    """The package fails the safe, non-installing v0.1 preflight."""


def _valid_path(name: str, *, directory: bool) -> bool:
    if directory:
        name = name.removesuffix("/")
    return (
        0 < len(name) <= 255
        and ".." not in name
        and "\\" not in name
        and ":" not in name
        and not name.startswith("/")
        and all(_SEGMENT.fullmatch(piece) for piece in name.split("/"))
    )


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise UnsafeAvatarArchive("Duplicate JSON object key")
        result[key] = value
    return result


def inspect_zip(source: BinaryIO) -> dict[str, object]:
    """Validate without extracting or executing any archive content.

    The caller must enforce the on-disk archive byte limit before opening it.
    Metadata is checked before payloads are streamed and CRC-verified.
    """
    try:
        with zipfile.ZipFile(source) as archive:
            infos = archive.infolist()
            if not infos or len(infos) > MAX_ENTRIES:
                raise UnsafeAvatarArchive("Invalid entry count")
            seen: set[str] = set()
            files: set[str] = set()
            total = 0
            manifest_info: zipfile.ZipInfo | None = None

            for info in infos:
                name = info.filename
                if not _valid_path(name, directory=info.is_dir()):
                    raise UnsafeAvatarArchive("Unsafe archive path")
                canonical = name.removesuffix("/").casefold()
                if canonical in seen:
                    raise UnsafeAvatarArchive("Duplicate archive path")
                seen.add(canonical)

                mode = info.external_attr >> 16
                kind = stat.S_IFMT(mode)
                if info.create_system == 3 and kind not in (0, stat.S_IFDIR, stat.S_IFREG):
                    raise UnsafeAvatarArchive("Links and special files are forbidden")
                if bool(info.flag_bits & 0x1):
                    raise UnsafeAvatarArchive("Encrypted ZIP entry")
                if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    raise UnsafeAvatarArchive("Unsupported ZIP compression")
                if info.is_dir():
                    if info.file_size != 0:
                        raise UnsafeAvatarArchive("Directory carries content")
                    continue

                if not name.lower().endswith((".json", ".moc3", ".png", ".jpg", ".jpeg", ".webp")):
                    raise UnsafeAvatarArchive("Unexpected avatar resource type")
                if info.file_size > MAX_FILE_BYTES or info.file_size < 0:
                    raise UnsafeAvatarArchive("Entry exceeds size bound")
                if info.file_size and (
                    info.compress_size == 0
                    or info.file_size > MAX_RATIO * info.compress_size
                ):
                    raise UnsafeAvatarArchive("Suspicious compression ratio")
                total += info.file_size
                if total > MAX_TOTAL_BYTES:
                    raise UnsafeAvatarArchive("Archive expands beyond limit")
                files.add(name)
                if name == "manifest.json":
                    if info.file_size > MAX_MANIFEST_BYTES:
                        raise UnsafeAvatarArchive("Manifest exceeds size bound")
                    manifest_info = info

            if manifest_info is None:
                raise UnsafeAvatarArchive("Root manifest.json is required")

            manifest_data = bytearray()
            for info in infos:
                if info.is_dir():
                    continue
                length = 0
                with archive.open(info, "r") as reader:
                    while data := reader.read(64 * 1024):
                        length += len(data)
                        if length > info.file_size or length > MAX_FILE_BYTES:
                            raise UnsafeAvatarArchive("Decompressed data exceeds bound")
                        if info.filename == "manifest.json":
                            manifest_data.extend(data)
                if length != info.file_size:
                    raise UnsafeAvatarArchive("ZIP entry size mismatch")

            manifest = json.loads(
                manifest_data.decode("utf-8"),
                object_pairs_hook=_unique_object,
            )
            if not isinstance(manifest, dict):
                raise UnsafeAvatarArchive("Invalid manifest object")
            identity = manifest.get("id")
            version = manifest.get("version")
            entry = manifest.get("entry")
            preview = manifest.get("preview")
            if (
                manifest.get("format") != "erciyuan-avatar"
                or manifest.get("formatVersion") != "0.1"
                or manifest.get("renderer") != "live2d-cubism"
                or manifest.get("runtimeProfile") != "native-r5-basic-v1"
                or not isinstance(identity, str)
                or not _PACKAGE_ID.fullmatch(identity)
                or not isinstance(version, str)
                or not _VERSION.fullmatch(version)
                or not isinstance(entry, str)
                or not _valid_path(entry, directory=False)
                or not entry.endswith(".model3.json")
                or entry not in files
                or not isinstance(preview, str)
                or not _valid_path(preview, directory=False)
                or not preview.endswith(".png")
                or preview not in files
            ):
                raise UnsafeAvatarArchive("Invalid or missing manifest resources")
            return {
                "id": identity,
                "version": version,
                "entries": len(files),
                "uncompressed_bytes": total,
                "preflight_only": True,
            }
    except (zipfile.BadZipFile, zipfile.LargeZipFile, UnicodeError, json.JSONDecodeError) as exc:
        raise UnsafeAvatarArchive("Invalid ZIP or manifest encoding/CRC") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip_file", type=Path, help="Local avatar ZIP (no files are extracted)")
    args = parser.parse_args()
    try:
        if args.zip_file.stat().st_size > MAX_ARCHIVE_BYTES:
            raise UnsafeAvatarArchive("ZIP file exceeds size bound")
        with args.zip_file.open("rb") as source:
            result = inspect_zip(source)
    except (OSError, UnsafeAvatarArchive) as exc:
        parser.exit(1, f"Avatar package rejected: {exc}\n")
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
