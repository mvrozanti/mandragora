"""Firefox automation: /ff, /ff action, /ff eval."""

import logging

from telegram import Update
from telegram.ext import ContextTypes

from bot.helpers import formatter, marionette_mgr

logger = logging.getLogger(__name__)


# -- Command handlers --


async def cmd_ff(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Open a URL in Firefox: /ff <url>."""
    if not context.args:
        await update.message.reply_text("Usage: /ff <url>")
        return

    url = context.args[0]
    if not url.startswith(("http://", "https://")):
        url = "https://" + url

    error = await marionette_mgr.open_url(url)
    if error:
        await update.message.reply_text(error)
    else:
        await update.message.reply_text(f"Opened: {url}")


async def cmd_ff_action(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Firefox tab actions: /ff action <tab_next|tab_prev|reload|close>."""
    if not context.args:
        await update.message.reply_text(
            "Usage: /ff action <tab_next|tab_prev|reload|close>"
        )
        return

    action = context.args[0].lower()
    valid_actions = {"tab_next", "tab_prev", "reload", "close"}

    if action not in valid_actions:
        await update.message.reply_text(
            f"Unknown action. Choose from: {', '.join(sorted(valid_actions))}"
        )
        return

    browser = await marionette_mgr.get_browser()
    if browser is None:
        await update.message.reply_text("Failed to connect to Firefox.")
        return

    try:
        if action == "tab_next":
            browser.switch_to_next_window()
            await update.message.reply_text("Switched to next tab.")
        elif action == "tab_prev":
            browser.switch_to_previous_window()
            await update.message.reply_text("Switched to previous tab.")
        elif action == "reload":
            browser.navigate(browser.get_url())
            await update.message.reply_text("Reloaded current page.")
        elif action == "close":
            # Close current tab by running JS to close it
            await marionette_mgr.eval_js("window.close()")
            await update.message.reply_text("Closed current tab.")
    except Exception as exc:
        logger.exception("Firefox action failed")
        await update.message.reply_text(f"Action failed: {exc}")


async def cmd_ff_eval(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Execute JavaScript in Firefox: /ff eval <js code>."""
    if not context.args:
        await update.message.reply_text("Usage: /ff eval <js code>")
        return

    js_code = " ".join(context.args)
    result = await marionette_mgr.eval_js(js_code)

    if result is None:
        await update.message.reply_text("JS execution returned no result.")
    elif result.startswith("Error"):
        await update.message.reply_text(formatter.wrap_code(result))
    else:
        for chunk in formatter.split_messages(result):
            await update.message.reply_text(formatter.wrap_code(chunk))
