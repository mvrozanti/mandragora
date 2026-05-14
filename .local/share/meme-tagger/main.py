"""meme-tagger Telegram bot entry. Mirrors llm-via-telegram/main.py."""
from __future__ import annotations

import logging
import sys

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

import config
from bot import handlers

logger = logging.getLogger(__name__)


def _is_authorized(update: Update) -> bool:
    user_id = str(update.effective_user.id) if update.effective_user else ""
    if user_id != config.ALLOWED_USER_ID:
        logger.warning("Unauthorized access attempt by user %s", user_id)
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
            logger.exception("Unhandled exception in handler")
            await update.message.reply_text(f"Internal error: {exc}")
    return wrapper


HELP_TEXT = (
    "\U0001f5bc meme-tagger -- Command Reference\n\n"
    "Send any image (as photo or as file) and the bot will tag it locally\n"
    "using a vision LLM, save it under ~/Pictures/tagged/<date>/, and write\n"
    "a sidecar JSON next to it for later search via `meme-find`.\n\n"
    "Tips\n"
    "  Send as *file* (not photo) for screenshots/text-heavy memes so OCR\n"
    "  works on full resolution. Telegram compresses photos.\n\n"
    "Commands\n"
    "  /start  -- Welcome\n"
    "  /help   -- This help\n"
    "  /status -- Show VLM model, incoming dir, current GPU holder\n"
    "  /retag  -- Reply to an image to re-tag it (overwrites sidecar)\n\n"
    "Only the authorized user can interact with this bot."
)


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "\U0001f5bc meme-tagger here. Send me an image and I'll tag it.\n"
        "/help for details."
    )


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(HELP_TEXT)


def build_application() -> Application:
    app = Application.builder().token(config.TELEGRAM_BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", _guard(cmd_start)))
    app.add_handler(CommandHandler("help", _guard(cmd_help)))
    app.add_handler(CommandHandler("status", _guard(handlers.cmd_status)))
    app.add_handler(CommandHandler("retag", _guard(handlers.cmd_retag)))

    app.add_handler(MessageHandler(filters.PHOTO, _guard(handlers.handle_photo)))
    app.add_handler(MessageHandler(filters.Document.IMAGE, _guard(handlers.handle_image_document)))

    return app


def main() -> None:
    errors = config.validate_config()
    if errors:
        for err in errors:
            logger.critical("Config error: %s", err)
        print("ERROR: Missing required configuration:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        sys.exit(1)

    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    )
    for noisy in ("httpx", "httpcore", "telegram.ext.Updater", "telegram.ext.Application", "PIL"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    app = build_application()

    async def post_init(application: Application) -> None:
        from telegram import BotCommand
        await application.bot.set_my_commands([
            BotCommand("start", "Start the bot"),
            BotCommand("help", "Show command reference"),
            BotCommand("status", "VLM model + GPU holder"),
            BotCommand("retag", "Re-tag the replied image"),
        ])
        logger.info("Bot commands menu set")

    app.post_init = post_init

    logger.info("meme-tagger bot starting; VLM=%s", config.VLM_MODEL)
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
