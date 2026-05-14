"""Sidecar writers: JSON (primary), xattr (best-effort), EXIF (JPEG only)."""
from __future__ import annotations

import logging
import os
import tempfile
from pathlib import Path

from . import schema

log = logging.getLogger(__name__)


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


def write_exif_if_jpeg(image_path: Path, tagged: schema.TaggedImage) -> bool:
    if tagged.source.format.upper() != "JPEG":
        return False
    try:
        from PIL import Image
        import piexif
    except ImportError:
        return False
    try:
        with Image.open(image_path) as img:
            exif_dict = piexif.load(img.info.get("exif", b""))
        comment = ("meme-tagger:" + " ".join(tagged.tags))[:65535]
        exif_dict.setdefault("Exif", {})[piexif.ExifIFD.UserComment] = (
            b"ASCII\x00\x00\x00" + comment.encode("ascii", errors="replace")
        )
        piexif.insert(piexif.dump(exif_dict), str(image_path))
        return True
    except Exception as exc:
        log.debug("EXIF write failed on %s: %s", image_path, exc)
        return False


def write_all(image_path: Path, tagged: schema.TaggedImage) -> Path:
    out = write_json(image_path, tagged)
    write_xattr(image_path, tagged)
    write_exif_if_jpeg(image_path, tagged)
    return out
