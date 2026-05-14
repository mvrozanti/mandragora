"""Image probing: sha256, format/dim/frames, midpoint-frame extraction for animated."""
from __future__ import annotations

import hashlib
import io
import logging
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageSequence

log = logging.getLogger(__name__)

SUPPORTED_FORMATS = frozenset({"JPEG", "PNG", "WEBP", "GIF", "BMP", "TIFF"})


@dataclass
class Probe:
    sha256: str
    size_bytes: int
    mtime: int
    format: str
    width: int
    height: int
    frames: int


def sha256_file(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            buf = f.read(chunk)
            if not buf:
                break
            h.update(buf)
    return h.hexdigest()


def probe(path: Path) -> Probe:
    st = path.stat()
    digest = sha256_file(path)
    with Image.open(path) as img:
        fmt = (img.format or "").upper()
        width, height = img.size
        frames = getattr(img, "n_frames", 1) or 1
    return Probe(
        sha256=digest,
        size_bytes=st.st_size,
        mtime=int(st.st_mtime),
        format=fmt,
        width=width,
        height=height,
        frames=frames,
    )


def load_representative_frame(path: Path, max_edge: int) -> bytes:
    with Image.open(path) as img:
        n = getattr(img, "n_frames", 1) or 1
        target = max(0, n // 2)
        if n > 1:
            for i, frame in enumerate(ImageSequence.Iterator(img)):
                if i == target:
                    chosen = frame.convert("RGB").copy()
                    break
            else:
                chosen = img.convert("RGB").copy()
        else:
            chosen = img.convert("RGB").copy()

    w, h = chosen.size
    longest = max(w, h)
    if longest > max_edge:
        scale = max_edge / longest
        chosen = chosen.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

    buf = io.BytesIO()
    chosen.save(buf, format="JPEG", quality=90)
    return buf.getvalue()
