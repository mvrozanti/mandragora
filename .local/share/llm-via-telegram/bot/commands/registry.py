"""Command registry: /reg cmd, /run, /reg list, /reg del."""

import logging

from telegram import Update
from telegram.ext import ContextTypes

from bot.helpers import formatter
from bot.helpers.shell import run_shell
from db import store

import config

logger = logging.getLogger(__name__)


# -- Command handlers --


async def cmd_reg_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Register a named command sequence: /reg cmd <name> <sequence>."""
    if len(context.args) < 2:
        await update.message.reply_text(
            "Usage: /reg cmd <name> <shell command>"
        )
        return

    name = context.args[0]
    sequence = " ".join(context.args[1:])
    store.save_command_entry(name, sequence)
    await update.message.reply_text(
        f"Command '{name}' registered:\n"
        f"{formatter.wrap_code(sequence)}"
    )


async def cmd_run(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Execute a registered command: /run <name>."""
    if not context.args:
        await update.message.reply_text("Usage: /run <name>")
        return

    name = context.args[0]
    sequence = store.get_command_entry(name)

    if sequence is None:
        available = store.list_commands()
        if available:
            cmd_list = "\n".join(
                f"  {n} -> {s}" for n, s in available
            )
            await update.message.reply_text(
                f"No command named '{name}'.\nRegistered:\n{cmd_list}"
            )
        else:
            await update.message.reply_text(
                f"No command named '{name}' and no commands registered yet.\n"
                f"Use /reg cmd <name> <command> to add one."
            )
        return

    await update.message.reply_text(f"Running '{name}'...")

    rc, stdout, stderr = await run_shell(sequence, env=config.x11_env())

    output = stdout.strip() or stderr.strip() or "(no output)"
    if rc != 0:
        output = f"Exit code: {rc}\n\n{output}"

    for chunk in formatter.split_messages(output):
        await update.message.reply_text(formatter.wrap_code(chunk))


async def cmd_reg_list(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """List all registered prompts and commands: /reg list."""
    prompts = store.list_prompts()
    commands = store.list_commands()

    if not prompts and not commands:
        await update.message.reply_text("Nothing registered yet.")
        return

    lines: list[str] = []
    if prompts:
        lines.append("Prompts:")
        lines.extend(f"  {p}" for p in prompts)
    if commands:
        lines.append("Commands:")
        lines.extend(f"  {n} -> {s}" for n, s in commands)

    text = "\n\n".join(lines)
    for chunk in formatter.split_messages(text):
        await update.message.reply_text(chunk)


async def cmd_reg_del(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Delete a registered prompt or command: /reg del <name>."""
    if not context.args:
        await update.message.reply_text("Usage: /reg del <name>")
        return

    name = context.args[0]

    deleted_prompt = store.delete_prompt(name)
    deleted_cmd = store.delete_command_entry(name)

    if deleted_prompt:
        await update.message.reply_text(f"Prompt '{name}' deleted.")
    elif deleted_cmd:
        await update.message.reply_text(f"Command '{name}' deleted.")
    else:
        await update.message.reply_text(
            f"No prompt or command named '{name}' found."
        )
