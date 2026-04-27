"""Browser action executor — parses LLM action tags and runs browser operations."""

import logging
import re

from telegram import Update
from telegram.ext import ContextTypes

from bot.helpers import marionette_mgr

logger = logging.getLogger(__name__)

# Match <action>NAME</action><arg>VALUE</arg> — arg is optional for some actions
_ACTION_RE = re.compile(
    r"<action>\s*(\w+)\s*</action>\s*(?:<arg>\s*(.*?)\s*</arg>)?",
    re.DOTALL,
)

# Actions that require an <arg> value
_ARG_ACTIONS = {"browser_open", "browser_eval"}


async def execute_action(action: str, arg: str | None) -> str:
    """Execute a single browser action. Returns the result as a string."""
    if action == "browser_open":
        if not arg:
            return "Error: browser_open requires a URL argument."
        err = await marionette_mgr.open_url(arg)
        return err or f"Opened: {arg}"

    if action == "browser_url":
        result = await marionette_mgr.get_url()
        return result or "Error: could not get URL."

    if action == "browser_title":
        result = await marionette_mgr.get_title()
        return result or "Error: could not get title."

    if action == "browser_eval":
        if not arg:
            return "Error: browser_eval requires a JavaScript argument."
        result = await marionette_mgr.eval_js(arg)
        if result is None:
            return "(no return value)"
        if result.startswith("Error"):
            return result
        return result

    if action == "browser_close_tab":
        result = await marionette_mgr.eval_js("window.close()")
        return "Tab closed." if result is None else result

    if action == "browser_kill":
        await marionette_mgr.kill_session()
        return "Firefox session killed."

    return f"Unknown action: {action}"


def extract_actions(text: str) -> list[tuple[str, str | None]]:
    """Parse all <action>/<arg> blocks from LLM output. Returns list of (action, arg)."""
    return [(m.group(1), m.group(2)) for m in _ACTION_RE.finditer(text)]


def strip_action_tags(text: str) -> str:
    """Remove action/arg tags from text so the user only sees the prose."""
    return _ACTION_RE.sub("", text).strip()


def has_actions(text: str) -> bool:
    """Check if text contains any action blocks."""
    return bool(_ACTION_RE.search(text))


# -- Command handlers for /browser --


async def cmd_browser(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Browser session management: /browser kill, /browser status."""
    if not context.args:
        await update.message.reply_text(
            "Usage:\n"
            "/browser kill -- Kill the Firefox session\n"
            "/browser status -- Check if Firefox is connected"
        )
        return

    sub = context.args[0].lower()

    if sub == "kill":
        await marionette_mgr.kill_session()
        await update.message.reply_text("Firefox session killed.")
    elif sub == "status":
        status = "connected" if marionette_mgr.is_alive() else "not connected"
        await update.message.reply_text(f"Firefox: {status}.")
    else:
        await update.message.reply_text(
            f"Unknown subcommand: {sub}. Use kill or status."
        )
