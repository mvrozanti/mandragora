"""Voice/audio note handler — transcribe (EN/PT auto-detect) and route to LLM."""

import logging
import os
import tempfile

from telegram import Update
from telegram.constants import ChatAction
from telegram.ext import ContextTypes

from bot.commands import intelligence
from bot.helpers.transcribe import transcribe

logger = logging.getLogger(__name__)


async def handle_voice(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    msg = update.message
    media = msg.voice or msg.audio or msg.video_note
    if media is None:
        return

    suffix = ".ogg" if msg.voice else ".bin"
    tmp_fd, tmp_path = tempfile.mkstemp(prefix="tg-voice-", suffix=suffix)
    os.close(tmp_fd)

    try:
        tg_file = await media.get_file()
        await tg_file.download_to_drive(tmp_path)

        await context.bot.send_chat_action(chat_id=msg.chat_id, action=ChatAction.TYPING)
        try:
            text, lang, conf = await transcribe(tmp_path)
        except Exception as exc:
            logger.exception("transcription failed")
            await msg.reply_text(f"Transcription failed: {exc}")
            return

        if not text:
            await msg.reply_text("(no speech detected)")
            return

        await msg.reply_text(f"\U0001f3a4 [{lang} {conf:.0%}] {text}")
        await intelligence.dispatch_query(update, text)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
