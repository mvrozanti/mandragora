import logging
import os
import sys
import tempfile
import time

from telegram import Update, BotCommand
from telegram.constants import ChatAction
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

import config
from transcribe import transcribe, warmup

try:
    from gpu_lock import gpu_lock, GpuBusy
    HAS_GPU_LOCK = True
except ImportError:
    HAS_GPU_LOCK = False

logger = logging.getLogger(__name__)


def _is_authorized(update: Update) -> bool:
    user_id = str(update.effective_user.id) if update.effective_user else ""
    if user_id != config.ALLOWED_USER_ID:
        logger.warning("unauthorized access attempt by user %s", user_id)
        return False
    return True


def _guard(handler):
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not _is_authorized(update):
            await update.message.reply_text("You are not authorized to use this bot.")
            return
        try:
            return await handler(update, context)
        except Exception as exc:
            logger.exception("unhandled exception in handler")
            await update.message.reply_text(f"Internal error: {exc}")
    return wrapper


HELP_TEXT = (
    "\U0001f3a4 STT-via-Telegram — bilingual (PT/EN) speech-to-text\n\n"
    "Send a voice note, audio file, or video note. I'll transcribe it.\n\n"
    "Modifiers (caption or reply):\n"
    "  /tr            translate to English\n"
    "  /lang en|pt    force a language (skips auto-detect)\n\n"
    "Slash commands:\n"
    "  /warmup        preload the model into VRAM\n"
    "  /status        show GPU lock holder and model state\n"
)


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "\U0001f44b STT bot ready. Send a voice note. /help for details."
    )


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(HELP_TEXT)


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    holder_msg = "(gpu_lock unavailable)"
    if HAS_GPU_LOCK:
        holder = gpu_lock.current_holder()
        if holder:
            since = holder.get("since", time.time())
            held = time.time() - since
            holder_msg = f"GPU held by {holder.get('name')} (pid={holder.get('pid')}, {held:.1f}s)"
        else:
            holder_msg = "GPU free"

    from transcribe import _model
    model_msg = "model loaded in VRAM" if _model is not None else "model not loaded"

    await update.message.reply_text(
        f"{holder_msg}\n{model_msg}\n"
        f"config: model={config.STT_MODEL} device={config.STT_DEVICE} compute={config.STT_COMPUTE_TYPE}"
    )


async def cmd_warmup(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await context.bot.send_chat_action(chat_id=update.message.chat_id, action=ChatAction.TYPING)

    async def _do():
        if HAS_GPU_LOCK:
            try:
                async with gpu_lock.acquire_async(config.GPU_LOCK_NAME, expected_seconds=60):
                    import asyncio
                    await asyncio.to_thread(warmup)
            except GpuBusy as busy:
                await update.message.reply_text(f"GPU busy — {busy}")
                return
        else:
            import asyncio
            await asyncio.to_thread(warmup)
        await update.message.reply_text("Model loaded.")

    await _do()


def _parse_modifiers(text: str | None) -> tuple[str, str | None]:
    """Return (task, language) parsed from caption / reply text."""
    task = "transcribe"
    language: str | None = None
    if not text:
        return task, language
    tokens = text.lower().split()
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in ("/tr", "/translate"):
            task = "translate"
        elif t in ("/lang", "/l") and i + 1 < len(tokens):
            cand = tokens[i + 1].strip(",.;:")
            if cand in config.ALLOWED_LANGS or len(cand) == 2:
                language = cand
            i += 1
        i += 1
    return task, language


async def handle_audio(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    msg = update.message
    media = msg.voice or msg.audio or msg.video_note or msg.video
    if media is None and msg.document and (msg.document.mime_type or "").startswith("audio"):
        media = msg.document
    if media is None:
        return

    suffix = ".ogg" if msg.voice else (
        os.path.splitext(getattr(media, "file_name", "") or "")[1] or ".bin"
    )
    tmp_fd, tmp_path = tempfile.mkstemp(prefix="stt-", suffix=suffix)
    os.close(tmp_fd)

    task, language = _parse_modifiers(msg.caption)

    try:
        tg_file = await media.get_file()
        await tg_file.download_to_drive(tmp_path)
        await context.bot.send_chat_action(chat_id=msg.chat_id, action=ChatAction.TYPING)

        started = time.monotonic()

        if HAS_GPU_LOCK:
            try:
                async with gpu_lock.acquire_async(
                    config.GPU_LOCK_NAME,
                    expected_seconds=config.GPU_EXPECTED_SECONDS,
                ):
                    result = await transcribe(tmp_path, language=language, task=task)
            except GpuBusy as busy:
                await msg.reply_text(f"GPU busy — {busy}. Try again in a moment.")
                return
        else:
            result = await transcribe(tmp_path, language=language, task=task)

        elapsed = time.monotonic() - started

        if not result.text:
            await msg.reply_text("(no speech detected)")
            return

        rtf = elapsed / result.duration if result.duration > 0 else 0
        header = (
            f"\U0001f3a4 [{result.language} {result.language_probability:.0%}"
            f" • {result.duration:.1f}s audio in {elapsed:.1f}s • {rtf:.2f}x]"
        )
        if result.task == "translate":
            header = f"\U0001f30d [translated → en] {header}"

        body = result.text
        chunks: list[str] = []
        first = f"{header}\n{body}"
        limit = 4000
        if len(first) <= limit:
            chunks.append(first)
        else:
            chunks.append(header)
            for i in range(0, len(body), limit):
                chunks.append(body[i:i + limit])

        for chunk in chunks:
            await msg.reply_text(chunk)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def build_application() -> Application:
    app = Application.builder().token(config.TELEGRAM_BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", _guard(cmd_start)))
    app.add_handler(CommandHandler("help", _guard(cmd_help)))
    app.add_handler(CommandHandler("status", _guard(cmd_status)))
    app.add_handler(CommandHandler("warmup", _guard(cmd_warmup)))
    app.add_handler(MessageHandler(
        filters.VOICE | filters.AUDIO | filters.VIDEO_NOTE | filters.VIDEO
        | (filters.Document.MimeType("audio/ogg") | filters.Document.MimeType("audio/mpeg")
           | filters.Document.MimeType("audio/wav") | filters.Document.MimeType("audio/x-wav")
           | filters.Document.MimeType("audio/flac") | filters.Document.MimeType("audio/mp4")),
        _guard(handle_audio),
    ))
    return app


def main() -> None:
    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    )
    for noisy in ("httpx", "httpcore", "telegram.ext.Updater", "telegram.ext.Application"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    errors = config.validate_config()
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        sys.exit(1)

    if not HAS_GPU_LOCK:
        logger.warning("gpu_lock module not on PYTHONPATH — running without GPU coordination")

    app = build_application()

    async def post_init(application: Application) -> None:
        await application.bot.set_my_commands([
            BotCommand("start", "Start the bot"),
            BotCommand("help", "Show command reference"),
            BotCommand("warmup", "Preload the model into VRAM"),
            BotCommand("status", "Show GPU lock holder and model state"),
        ])
        logger.info("bot commands menu set")

    app.post_init = post_init

    logger.info("STT bot starting; listening for audio...")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
