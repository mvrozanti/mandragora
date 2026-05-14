"""Photo + image-document handlers: save -> tag -> reply with summary."""
from __future__ import annotations

import logging
import secrets
from datetime import datetime
from pathlib import Path

from telegram import Update
from telegram.ext import ContextTypes

import config
from pipeline import dispatcher, preprocess, sidecar

log = logging.getLogger(__name__)

IMAGE_MIME_PREFIXES = ("image/",)
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff", ".tif"}


def _ext_from_filename(name: str | None, fallback: str = ".jpg") -> str:
    if not name:
        return fallback
    suffix = Path(name).suffix.lower()
    if suffix in IMAGE_EXTS:
        return suffix
    return fallback


def _date_dir() -> Path:
    d = config.INCOMING_ROOT / datetime.now().strftime("%Y-%m-%d")
    d.mkdir(parents=True, exist_ok=True)
    return d


async def _download_to_tmp(file_obj, ext: str, dest_dir: Path) -> Path:
    tmp = dest_dir / f"_tmp-{secrets.token_hex(6)}{ext}"
    await file_obj.download_to_drive(custom_path=str(tmp))
    return tmp


def _finalize_path(tmp: Path, ext: str, dest_dir: Path) -> Path:
    probe = preprocess.probe(tmp)
    final = dest_dir / f"{probe.sha256[:12]}{ext}"
    if final.exists():
        tmp.unlink(missing_ok=True)
        return final
    tmp.rename(final)
    return final


def _format_summary(result) -> str:
    t = result.tagged
    lines = []
    head = f"#{t.content_type}"
    if t.category:
        head += f" #{t.category}"
    if t.template:
        head += f" #tpl_{t.template}"
    for ch in t.characters[:4]:
        head += f" #char_{ch}"
    lines.append(head)
    if t.description:
        lines.append(t.description)
    if t.punchline:
        lines.append(f"-- {t.punchline}")
    if t.text_ocr:
        text = " / ".join(t.text_ocr)[:300]
        lines.append(f'text: "{text}"')
    suffix = " (cached)" if result.cached else f" ({result.elapsed_seconds:.1f}s)"
    lines.append(suffix.strip())
    return "\n".join(lines)


async def _process_image(
    update: Update, context: ContextTypes.DEFAULT_TYPE, file_obj, ext: str
) -> None:
    dest = _date_dir()
    msg = update.message

    tmp = await _download_to_tmp(file_obj, ext, dest)
    final = _finalize_path(tmp, ext, dest)
    log.info("received image -> %s", final)

    async def on_busy(busy):
        try:
            await msg.reply_text(f"GPU busy with {busy.holder.get('name','?') if busy.holder else '?'}, retrying...")
        except Exception:
            pass

    try:
        result = await dispatcher.tag_image_with_retry(final, on_busy=on_busy)
    except Exception as exc:
        log.exception("tagging failed for %s", final)
        await msg.reply_text(f"tagging failed: {exc}")
        return

    await msg.reply_text(_format_summary(result))


async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.photo:
        return
    photo = update.message.photo[-1]
    file_obj = await context.bot.get_file(photo.file_id)
    await _process_image(update, context, file_obj, ".jpg")


async def handle_image_document(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.document:
        return
    doc = update.message.document
    mime = doc.mime_type or ""
    is_image_mime = any(mime.startswith(p) for p in IMAGE_MIME_PREFIXES)
    ext = _ext_from_filename(doc.file_name)
    is_image_ext = ext in IMAGE_EXTS
    if not (is_image_mime or is_image_ext):
        return
    file_obj = await context.bot.get_file(doc.file_id)
    await _process_image(update, context, file_obj, ext)


async def cmd_retag(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    msg = update.message
    if not msg or not msg.reply_to_message:
        await msg.reply_text("Reply to an image with /retag to re-tag it.")
        return
    replied = msg.reply_to_message

    file_obj = None
    ext = ".jpg"
    if replied.photo:
        photo = replied.photo[-1]
        file_obj = await context.bot.get_file(photo.file_id)
        ext = ".jpg"
    elif replied.document:
        doc = replied.document
        mime = doc.mime_type or ""
        ext_guess = _ext_from_filename(doc.file_name)
        if not (mime.startswith("image/") or ext_guess in IMAGE_EXTS):
            await msg.reply_text("Replied message has no image.")
            return
        file_obj = await context.bot.get_file(doc.file_id)
        ext = ext_guess
    else:
        await msg.reply_text("Replied message has no image.")
        return

    dest = _date_dir()
    tmp = await _download_to_tmp(file_obj, ext, dest)
    final = _finalize_path(tmp, ext, dest)
    existing_sidecar = sidecar.sidecar_path(final)
    if existing_sidecar.exists():
        existing_sidecar.unlink()
    try:
        result = await dispatcher.tag_image_with_retry(final, force=True)
    except Exception as exc:
        await msg.reply_text(f"retag failed: {exc}")
        return
    await msg.reply_text(_format_summary(result))


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    msg = update.message
    try:
        from gpu_lock import gpu_lock
        holder = gpu_lock.current_holder()
    except Exception:
        holder = None
    pieces = [f"VLM model: {config.VLM_MODEL}", f"Incoming root: {config.INCOMING_ROOT}"]
    if holder:
        pieces.append(f"GPU holder: {holder.get('name','?')} (pid {holder.get('pid','?')})")
    else:
        pieces.append("GPU free")
    await msg.reply_text("\n".join(pieces))
