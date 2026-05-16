"""meme-find: locate tagged images by tag / template / character / OCR / free text."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

DEFAULT_ROOTS = (".", "~/Pictures", "~/Downloads")
SIDECAR_SUFFIX = ".tags.json"


def _expand_roots(env_value: str | None) -> list[Path]:
    raw = env_value if env_value is not None else os.pathsep.join(DEFAULT_ROOTS)
    seen: dict[Path, None] = {}
    for part in raw.split(os.pathsep):
        part = part.strip()
        if not part:
            continue
        p = Path(part).expanduser().resolve()
        if p not in seen:
            seen[p] = None
    return [p for p in seen if p.exists()]


def _iter_sidecars(roots: list[Path]) -> list[Path]:
    out: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob("*" + SIDECAR_SUFFIX):
            if p.is_file():
                out.append(p)
    return out


def _load(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _image_path(sidecar: dict, sidecar_file: Path) -> Path:
    src = sidecar.get("source", {}).get("path", "")
    if src and Path(src).exists():
        return Path(src)
    name = sidecar_file.name
    if name.endswith(SIDECAR_SUFFIX):
        candidate = sidecar_file.with_name(name[: -len(SIDECAR_SUFFIX)])
        if candidate.exists():
            return candidate
    return Path(src or sidecar_file)


def _parse_since(value: str) -> float:
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(value, fmt).timestamp()
        except ValueError:
            continue
    raise argparse.ArgumentTypeError(f"unrecognized date: {value!r}")


def _matches(
    sidecar: dict,
    *,
    must_tags: list[str],
    text_substrs: list[str],
    content_type: str | None,
    since_ts: float | None,
    until_ts: float | None,
    free_regex: re.Pattern | None,
) -> bool:
    tags = sidecar.get("tags", []) or []
    tag_set = {str(t).lower() for t in tags}
    for needle in must_tags:
        n = needle.lower()
        if n in tag_set:
            continue
        if any(n in t for t in tag_set):
            continue
        return False

    if content_type is not None:
        if str(sidecar.get("content_type", "")).lower() != content_type.lower():
            return False

    if text_substrs:
        haystack = " ".join(sidecar.get("text_ocr", []) or []).lower()
        for substr in text_substrs:
            if substr.lower() not in haystack:
                return False

    if since_ts is not None or until_ts is not None:
        mtime = sidecar.get("source", {}).get("mtime", 0) or 0
        if since_ts is not None and mtime < since_ts:
            return False
        if until_ts is not None and mtime > until_ts:
            return False

    if free_regex is not None:
        blob_parts = [
            sidecar.get("description", "") or "",
            sidecar.get("context", "") or "",
            sidecar.get("punchline", "") or "",
        ]
        blob = "\n".join(blob_parts)
        if not free_regex.search(blob):
            return False

    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="meme-find", description=__doc__)
    parser.add_argument("terms", nargs="*", help="Tag substrings (AND)")
    parser.add_argument("--text", action="append", default=[], help="OCR substring (case-insensitive); repeatable")
    parser.add_argument("--type", dest="content_type", help="content_type filter (meme, photo, screenshot_text, ...)")
    parser.add_argument("--since", type=_parse_since, help="mtime >= YYYY-MM-DD")
    parser.add_argument("--until", type=_parse_since, help="mtime <= YYYY-MM-DD")
    parser.add_argument("-F", "--free", help="Regex against description/context/punchline")
    parser.add_argument("--json", action="store_true", help="Emit full sidecar JSON (one per line)")
    parser.add_argument("--roots", help="Override MEME_TAGGER_SEARCH_ROOTS (colon-separated)")
    args = parser.parse_args(argv)

    roots = _expand_roots(args.roots if args.roots is not None else os.getenv("MEME_TAGGER_SEARCH_ROOTS"))
    if not roots:
        print("no search roots exist", file=sys.stderr)
        return 2

    free_regex = re.compile(args.free, re.IGNORECASE) if args.free else None

    matches: list[tuple[Path, dict]] = []
    for sidecar_path in _iter_sidecars(roots):
        sc = _load(sidecar_path)
        if sc is None:
            continue
        if _matches(
            sc,
            must_tags=args.terms,
            text_substrs=args.text,
            content_type=args.content_type,
            since_ts=args.since,
            until_ts=args.until,
            free_regex=free_regex,
        ):
            matches.append((_image_path(sc, sidecar_path), sc))

    matches.sort(key=lambda mt: mt[1].get("source", {}).get("mtime", 0), reverse=True)

    if args.json:
        for _img, sc in matches:
            print(json.dumps(sc, ensure_ascii=False))
    else:
        for img, _sc in matches:
            print(img)

    return 0 if matches else 1


if __name__ == "__main__":
    sys.exit(main())
