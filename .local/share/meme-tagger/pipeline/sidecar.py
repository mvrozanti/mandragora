"""Sidecar writers: JSON (primary), xattr (best-effort), XMP/EXIF via exiftool."""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from . import schema

log = logging.getLogger(__name__)

XMP_FORMATS = frozenset({"JPEG", "PNG", "WEBP", "TIFF", "GIF"})


def sidecar_path(image_path: Path) -> Path:
    return image_path.with_name(image_path.name + ".tags.json")


def read_sidecar(image_path: Path) -> schema.TaggedImage | None:
    p = sidecar_path(image_path)
    if not p.exists():
        return None
    try:
        return schema.TaggedImage.from_json_file(p)
    except Exception as exc:
        log.warning("failed to read sidecar %s: %s", p, exc)
        return None


def already_tagged(image_path: Path, sha256: str) -> schema.TaggedImage | None:
    existing = read_sidecar(image_path)
    if existing is None:
        return None
    if existing.schema_version != schema.SCHEMA_VERSION:
        return None
    if existing.source.sha256 != sha256:
        return None
    return existing


def write_json(image_path: Path, tagged: schema.TaggedImage) -> Path:
    out = sidecar_path(image_path)
    payload = tagged.to_json()
    fd, tmp = tempfile.mkstemp(prefix=".meme-tagger-", dir=str(out.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(payload)
        os.replace(tmp, out)
    except Exception:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise
    return out


def write_xattr(image_path: Path, tagged: schema.TaggedImage) -> bool:
    try:
        attr = b"user.meme_tagger.tags"
        value = (" ".join(tagged.tags)).encode("utf-8")
        os.setxattr(str(image_path), attr, value)
        return True
    except (OSError, AttributeError) as exc:
        log.debug("xattr write failed on %s: %s", image_path, exc)
        return False


def write_xmp(image_path: Path, tagged: schema.TaggedImage) -> bool:
    if tagged.source.format.upper() not in XMP_FORMATS:
        return False
    exiftool = shutil.which("exiftool")
    if not exiftool:
        log.debug("exiftool not in PATH; skipping XMP write")
        return False

    description = tagged.description or ""
    title_bits = [tagged.content_type]
    if tagged.template:
        title_bits.append(tagged.template)
    if tagged.category:
        title_bits.append(tagged.category)
    title = " / ".join(b for b in title_bits if b)

    args = [
        exiftool,
        "-overwrite_original",
        "-q", "-q",
        "-codedcharacterset=utf8",
        "-XMP-dc:Subject=",
        "-IPTC:Keywords=",
    ]
    for tag in tagged.tags:
        args.append(f"-XMP-dc:Subject+={tag}")
        args.append(f"-IPTC:Keywords+={tag}")
    if description:
        args.append(f"-XMP-dc:Description={description}")
        args.append(f"-EXIF:ImageDescription={description}")
    if title:
        args.append(f"-XMP-dc:Title={title}")
    args.append(str(image_path))

    try:
        result = subprocess.run(args, capture_output=True, timeout=30)
        if result.returncode != 0:
            log.warning("exiftool failed on %s: %s", image_path, result.stderr.decode(errors="replace"))
            return False
        return True
    except Exception as exc:
        log.warning("exiftool exception on %s: %s", image_path, exc)
        return False


def write_all(image_path: Path, tagged: schema.TaggedImage) -> Path:
    out = write_json(image_path, tagged)
    write_xattr(image_path, tagged)
    write_xmp(image_path, tagged)
    return out
