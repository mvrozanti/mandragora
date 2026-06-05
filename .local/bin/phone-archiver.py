#!/usr/bin/env python3
import fcntl
import hashlib
import logging
import mimetypes
import os
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    from PIL import Image, ExifTags
    _EXIF_DATE_TAG = next(
        (k for k, v in ExifTags.TAGS.items() if v == "DateTimeOriginal"),
        None,
    )
except ImportError:
    Image = None
    _EXIF_DATE_TAG = None

HOME = Path(os.environ.get("HOME", "/home/m"))
INBOX_ROOT = HOME / "Pictures" / "PhoneInbox"
LOCK_PATH = HOME / ".cache" / "phone-archiver.lock"

MIN_AGE_SECONDS = 60
SKIP_NAMES = {".stfolder", ".stversions", ".stignore"}
SKIP_SUFFIXES = (".tmp", ".partial", ".part")
SKIP_INFIX = ".sync-conflict-"

PHOTO_ROOT = HOME / "Pictures" / "Photos"
VIDEO_ROOT = HOME / "Videos" / "Phone"
SCREENSHOT_ROOT = HOME / "Documents" / "PhoneScreenshots"
DOWNLOAD_ROOT = HOME / "Documents" / "PhoneDownloads"


def image_or_video(path):
    mime, _ = mimetypes.guess_type(path.name)
    if mime is None:
        return None
    if mime.startswith("image/"):
        return "image"
    if mime.startswith("video/"):
        return "video"
    return None


def camera_router(path):
    kind = image_or_video(path)
    if kind == "video":
        return VIDEO_ROOT
    return PHOTO_ROOT


def screenshot_router(_path):
    return SCREENSHOT_ROOT


def whatsapp_router(path):
    kind = image_or_video(path)
    if kind == "video":
        return VIDEO_ROOT
    if kind == "image":
        return PHOTO_ROOT
    return DOWNLOAD_ROOT


def download_router(_path):
    return DOWNLOAD_ROOT


BUCKETS = [
    ("camera", camera_router),
    ("screenshots", screenshot_router),
    ("whatsapp", whatsapp_router),
    ("downloads", download_router),
]


def should_skip(path, now):
    name = path.name
    if name in SKIP_NAMES:
        return True
    if name.endswith(SKIP_SUFFIXES):
        return True
    if SKIP_INFIX in name:
        return True
    try:
        if now - path.stat().st_mtime < MIN_AGE_SECONDS:
            return True
    except FileNotFoundError:
        return True
    return False


def exif_date(path):
    if Image is None or _EXIF_DATE_TAG is None:
        return None
    try:
        with Image.open(path) as img:
            exif = img.getexif()
            if not exif:
                return None
            raw = exif.get(_EXIF_DATE_TAG)
            if not raw:
                return None
            return datetime.strptime(raw, "%Y:%m:%d %H:%M:%S")
    except (OSError, ValueError, KeyError):
        return None


def file_date(path):
    return exif_date(path) or datetime.fromtimestamp(path.stat().st_mtime)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def unique_dest(dest_dir, name, short_hash):
    candidate = dest_dir / name
    if not candidate.exists():
        return candidate
    stem = candidate.stem
    suffix = candidate.suffix
    return dest_dir / f"{stem}-{short_hash[:8]}{suffix}"


def archive_one(src, dest_root, log):
    date = file_date(src)
    dest_dir = dest_root / f"{date.year:04d}" / f"{date.month:02d}"
    dest_dir.mkdir(parents=True, exist_ok=True)

    src_hash = sha256_of(src)

    existing = dest_dir / src.name
    if existing.exists():
        if sha256_of(existing) == src_hash:
            src.unlink()
            log.info("dup-removed: %s (already at %s)", src, existing)
            return

    dest = unique_dest(dest_dir, src.name, src_hash)
    partial = dest.with_suffix(dest.suffix + ".partial")
    shutil.copy2(src, partial)

    if sha256_of(partial) != src_hash:
        log.error("hash mismatch on copy: %s -> %s; leaving source", src, partial)
        partial.unlink(missing_ok=True)
        return

    partial.rename(dest)
    src.unlink()
    log.info("archived: %s -> %s", src, dest)


def walk_bucket(bucket_dir, router, log):
    now = time.time()
    for path in bucket_dir.rglob("*"):
        if not path.is_file():
            continue
        if should_skip(path, now):
            continue
        if any(part in SKIP_NAMES for part in path.relative_to(bucket_dir).parts):
            continue
        try:
            archive_one(path, router(path), log)
        except Exception as e:
            log.exception("failed: %s: %s", path, e)


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    log = logging.getLogger("phone-archiver")

    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK_PATH, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log.info("another instance running; exiting")
            return 0

        if not INBOX_ROOT.exists():
            log.info("inbox root %s missing; nothing to do", INBOX_ROOT)
            return 0

        for name, router in BUCKETS:
            bucket_dir = INBOX_ROOT / name
            if not bucket_dir.is_dir():
                continue
            walk_bucket(bucket_dir, router, log)

    return 0


if __name__ == "__main__":
    sys.exit(main())
