"""Entry point — bot initialization, command registration, /help, /start."""

import logging
import sys

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

import config
from bot.commands import browser, firefox, intelligence, mpv, registry, system, voice
from db import store

logger = logging.getLogger(__name__)


# -- Access control --


def _is_authorized(update: Update) -> bool:
    """Check if the user is in the allowed list."""
    user_id = str(update.effective_user.id) if update.effective_user else ""
    if user_id != config.ALLOWED_USER_ID:
        logger.warning("Unauthorized access attempt by user %s", user_id)
        return False
    return True


def _guard(handler):
    """Wrap a handler to enforce user whitelist."""
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not _is_authorized(update):
            await update.message.reply_text(
                "You are not authorized to use this bot."
            )
            return
        try:
            return await handler(update, context)
        except Exception as exc:
            logger.exception("Unhandled exception in handler")
            await update.message.reply_text(
                f"Internal error: {exc}"
            )
    return wrapper


# -- /start and /help --


HELP_TEXT = (
    "\U0001f916 LLM via Telegram -- Command Reference\n\n"
    "LLM\n"
    "  Plain text  -- Send to local LLM\n"
    "  Voice note  -- Transcribed (EN/PT auto) then sent to LLM\n"
    "  /context   -- Show model, system prompt sizes, history, token budget\n"
    "  /clear     -- Clear conversation history\n"
    "  /think     -- Toggle thinking display (enabled/disabled)\n\n"
    "Personas\n"
    "  /p <name> <query> -- Query using a registered persona\n\n"
    "System\n"
    "  /sh <cmd> -- Run a shell command\n"
    "  /sudopass <pw> -- Cache sudo password (in-memory only)\n"
    "  /sudo <cmd> -- Run with sudo (needs cached password)\n"
    "  /term <cmd> -- Open in new terminal\n"
    "  /hotkey <keys> -- Simulate X11 hotkeys (e.g. ctrl+shift+t)\n\n"
    "Firefox\n"
    "  /ff <url> -- Open URL in Firefox\n"
    "  /browser kill -- Kill the Firefox session\n"
    "  /browser status -- Check Firefox connection\n\n"
    "MPV\n"
    "  /mpv <action> -- Control MPV (pause, stop, next, volume, etc.)\n\n"
    "Registry\n"
    "  /reg prompt <name> <instruction> -- Save a persona prompt\n"
    "  /reg cmd <name> <sequence> -- Save a shell command shortcut\n"
    "  /reg list -- List all registered items\n"
    "  /reg del <name> -- Delete a registered item\n"
    "  /run <name> -- Execute a registered command\n\n"
    "Only the authorized user can interact with this bot."
)


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /start -- send a welcome message."""
    await update.message.reply_text(
        "\U0001f44b Welcome! I'm your system command center.\n"
        "Send /help to see all available commands."
    )


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /help -- show command reference."""
    await update.message.reply_text(HELP_TEXT)


async def cmd_catch_all(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    text = update.message.text.strip()
    known_prefixes = (
        "/sh", "/p", "/ff", "/browser", "/mpv", "/term",
        "/reg", "/run", "/sudo", "/hotkey",
        "/context", "/clear", "/think",
    )
    if text.startswith("/"):
        matches = [p for p in known_prefixes if text.startswith(p)]
        if matches:
            await update.message.reply_text(
                f"Unknown command '{text}'. Did you mean '{matches[0]}'?\n"
                f"Send /help for the full list."
            )
            return

    await intelligence.handle_text(update, context)


# -- Bot setup --


def build_application() -> Application:
    """Build and configure the Telegram bot application."""
    app = Application.builder().token(config.TELEGRAM_BOT_TOKEN).build()

    # -- Core --
    app.add_handler(CommandHandler("start", _guard(cmd_start)))
    app.add_handler(CommandHandler("help", _guard(cmd_help)))

    # -- Intelligence --
    app.add_handler(CommandHandler("context", _guard(intelligence.cmd_context)))
    app.add_handler(CommandHandler("clear", _guard(intelligence.cmd_clear)))
    app.add_handler(CommandHandler("think", _guard(intelligence.cmd_think)))
    app.add_handler(CommandHandler("p", _guard(intelligence.cmd_p)))

    # -- System --
    app.add_handler(CommandHandler("sh", _guard(system.cmd_sh)))
    app.add_handler(CommandHandler("sudopass", _guard(system.cmd_sudopass)))
    app.add_handler(CommandHandler("sudo", _guard(system.cmd_sudo)))
    app.add_handler(CommandHandler("term", _guard(system.cmd_term)))
    app.add_handler(CommandHandler("hotkey", _guard(system.cmd_hotkey)))

    # -- Firefox --
    app.add_handler(CommandHandler("ff", _guard(firefox.cmd_ff)))
    app.add_handler(CommandHandler("browser", _guard(browser.cmd_browser)))

    # -- MPV --
    app.add_handler(CommandHandler("mpv", _guard(mpv.cmd_mpv)))

    # -- Registry --
    app.add_handler(CommandHandler("reg", _guard(_reg_dispatcher)))
    app.add_handler(CommandHandler("run", _guard(registry.cmd_run)))

    # -- Voice / audio --
    app.add_handler(MessageHandler(
        filters.VOICE | filters.AUDIO | filters.VIDEO_NOTE,
        _guard(voice.handle_voice),
    ))

    # -- Catch-all -- must come last
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, _guard(cmd_catch_all)))

    return app


async def _reg_dispatcher(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Route /reg subcommands: prompt, cmd, list, del."""
    if not context.args:
        await update.message.reply_text(
            "Usage:\n"
            "/reg prompt <name> <instruction> -- Save a persona\n"
            "/reg cmd <name> <command> -- Save a shell command\n"
            "/reg list -- List all registered items\n"
            "/reg del <name> -- Delete a registered item"
        )
        return

    sub = context.args[0].lower()
    remaining_args = context.args[1:]

    old_args = context.args
    context.args = remaining_args

    if sub == "prompt":
        await intelligence.cmd_reg_prompt(update, context)
    elif sub in ("cmd", "command"):
        await registry.cmd_reg_cmd(update, context)
    elif sub == "list":
        await registry.cmd_reg_list(update, context)
    elif sub in ("del", "delete", "rm"):
        await registry.cmd_reg_del(update, context)
    else:
        await update.message.reply_text(
            f"Unknown subcommand: {sub}. Use prompt, cmd, list, or del."
        )

    context.args = old_args


def main() -> None:
    """Main entry point."""
    # -- Validate config --
    errors = config.validate_config()
    if errors:
        for err in errors:
            logger.critical("Config error: %s", err)
        print("ERROR: Missing required configuration:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        sys.exit(1)

    # -- Logging --
    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    )
    # python-telegram-bot uses httpx and logs full request URLs at INFO,
    # which embeds the bot token in the path. Mute httpx to WARNING so
    # tokens never reach the systemd journal.
    for noisy in ("httpx", "httpcore", "telegram.ext.Updater", "telegram.ext.Application"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    # -- Init database --
    store.init_db()

    # -- Build and run --
    app = build_application()

    async def post_init(application: Application) -> None:
        from telegram import BotCommand

        await application.bot.set_my_commands([
            BotCommand("start", "Start the bot"),
            BotCommand("help", "Show command reference"),
            BotCommand("context", "Show model, system prompt, history, token use"),
            BotCommand("clear", "Clear conversation history"),
            BotCommand("think", "Toggle thinking display"),
            BotCommand("p", "Query with persona"),
            BotCommand("sh", "Run shell command"),
            BotCommand("sudopass", "Cache sudo password"),
            BotCommand("sudo", "Run with sudo"),
            BotCommand("term", "Open in terminal"),
            BotCommand("hotkey", "Simulate X11 hotkeys"),
            BotCommand("ff", "Open URL in Firefox"),
            BotCommand("browser", "Kill/check Firefox session"),
            BotCommand("mpv", "Control MPV"),
            BotCommand("reg", "Register prompts/commands"),
            BotCommand("run", "Run a registered command"),
        ])
        logger.info("Bot commands menu set")

    app.post_init = post_init

    logger.info("Bot is starting. Listening for updates...")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
