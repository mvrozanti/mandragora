"""meme-tagger CLI: tag a file or recursively tag a directory."""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from pathlib import Path

import config
from pipeline import dispatcher, preprocess, sidecar

log = logging.getLogger("meme-tagger")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff", ".tif"}


def _setup_logging(level: str) -> None:
    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        level=getattr(logging, level.upper(), logging.INFO),
    )
    for noisy in ("httpx", "httpcore", "PIL"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def _iter_images(root: Path, recursive: bool) -> list[Path]:
    if root.is_file():
        return [root]
    if not recursive:
        return sorted(p for p in root.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS)
    return sorted(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_EXTS)


async def _busy_handler(busy):
    log.warning("GPU busy: %s; retrying in %.0fs", busy, config.GPU_BUSY_RETRY_SECONDS)


async def cmd_tag(args: argparse.Namespace) -> int:
    root = Path(args.path).expanduser().resolve()
    if not root.exists():
        log.error("path does not exist: %s", root)
        return 2

    images = _iter_images(root, recursive=args.recursive)
    if not images:
        log.warning("no images found under %s", root)
        return 0

    total = len(images)
    tagged_n = 0
    skipped_n = 0
    failed_n = 0

    for i, img in enumerate(images, 1):
        try:
            if not args.force:
                p = preprocess.probe(img)
                cached = sidecar.already_tagged(img, p.sha256)
                if cached is not None:
                    skipped_n += 1
                    if args.verbose:
                        log.info("[%d/%d] SKIP %s (already tagged)", i, total, img)
                    continue
            result = await dispatcher.tag_image_with_retry(
                img, force=args.force, on_busy=_busy_handler,
            )
            tagged_n += 1
            summary = _summary(result.tagged)
            log.info(
                "[%d/%d] OK %.1fs %s -- %s",
                i, total, result.elapsed_seconds, img.name, summary,
            )
        except Exception as exc:
            failed_n += 1
            log.exception("[%d/%d] FAIL %s: %s", i, total, img, exc)
            if args.fail_fast:
                return 1

    log.info(
        "done: %d tagged, %d skipped, %d failed (total %d)",
        tagged_n, skipped_n, failed_n, total,
    )
    return 0 if failed_n == 0 else 1


def _summary(tagged) -> str:
    bits = [tagged.content_type]
    if tagged.template:
        bits.append(f"tpl={tagged.template}")
    if tagged.characters:
        bits.append("chars=" + ",".join(tagged.characters[:4]))
    if tagged.text_ocr:
        snippet = " | ".join(tagged.text_ocr)[:60]
        bits.append(f'text="{snippet}"')
    return " ".join(bits)


def cmd_info(args: argparse.Namespace) -> int:
    image_path = Path(args.path).expanduser().resolve()
    if not image_path.exists():
        log.error("image not found: %s", image_path)
        return 2
    existing = sidecar.read_sidecar(image_path)
    if existing is None:
        log.error("no sidecar for %s", image_path)
        return 1
    print(existing.to_json())
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="meme-tagger", description=__doc__)
    parser.add_argument("--log-level", default=config.LOG_LEVEL, help="DEBUG/INFO/WARNING/ERROR")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_tag = sub.add_parser("tag", help="Tag an image or directory")
    p_tag.add_argument("path", help="Image file or directory")
    p_tag.add_argument("-r", "--recursive", action="store_true", help="Recurse into subdirs")
    p_tag.add_argument("-f", "--force", action="store_true", help="Re-tag even if sidecar exists")
    p_tag.add_argument("-v", "--verbose", action="store_true", help="Log SKIPs")
    p_tag.add_argument("--fail-fast", action="store_true", help="Abort on first failure")

    p_info = sub.add_parser("info", help="Print existing sidecar JSON")
    p_info.add_argument("path", help="Image file")

    args = parser.parse_args(argv)
    _setup_logging(args.log_level)

    if args.cmd == "tag":
        return asyncio.run(cmd_tag(args))
    if args.cmd == "info":
        return cmd_info(args)

    parser.error(f"unknown command {args.cmd!r}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
