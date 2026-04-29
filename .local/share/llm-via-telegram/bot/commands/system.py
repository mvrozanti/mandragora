"""System control: /sh, /sudo, /sudopass, /term, /hotkey, /screenshot."""

import logging
import os

import pexpect
from telegram import Update
from telegram.ext import ContextTypes

import config
from bot.helpers import formatter, sudo_cache
from bot.helpers.shell import run_shell

logger = logging.getLogger(__name__)


# -- Command handlers --


async def cmd_sh(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Run a shell command: /sh <command>."""
    cmd = " ".join(context.args) if context.args else ""
    if not cmd:
        await update.message.reply_text("Usage: /sh <command>")
        return

    await update.message.reply_text("Running...")

    rc, stdout, stderr = await run_shell(cmd, env=config.x11_env())

    output = stdout.strip() or stderr.strip() or "(no output)"
    if rc != 0:
        output = f"Exit code: {rc}\n\n{output}"

    for chunk in formatter.split_messages(output):
        await update.message.reply_text(formatter.wrap_code(chunk))


async def cmd_sudopass(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Cache the sudo password: /sudopass <password>. With no args, shows status."""
    password = " ".join(context.args) if context.args else ""
    if not password:
        if sudo_cache.SudoCache.get():
            await update.message.reply_text(
                "Sudo password is currently cached and will expire on timeout or bot restart."
            )
        else:
            await update.message.reply_text(
                "No sudo password cached. Send /sudopass <password> to cache it."
            )
        return

    sudo_cache.SudoCache.set(password)
    await update.message.reply_text(
        "Sudo password cached in memory (cleared on bot restart or timeout)."
    )


async def cmd_sudo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Run a command with sudo: /sudo <command>."""
    cmd = " ".join(context.args) if context.args else ""
    if not cmd:
        await update.message.reply_text("Usage: /sudo <command>")
        return

    cached_pw = sudo_cache.SudoCache.get()
    if cached_pw is None:
        await update.message.reply_text(
            "No sudo password cached. Send /sudopass <password> first, then retry."
        )
        return

    await _run_sudo_command(update, cmd, cached_pw)


async def _run_sudo_command(update: Update, cmd: str, password: str) -> None:
    """Execute a sudo command using pexpect to inject the password."""
    logger.info("Running sudo command: %s", cmd)

    try:
        child = pexpect.spawn(
            "sudo", ["-S", "--"] + cmd.split(),
            timeout=120,
            env={**os.environ, **config.x11_env()},
            encoding="utf-8",
            codec_errors="replace",
        )

        idx = child.expect(
            [r"\[sudo\].*password", r"[Ss]orry, try again", pexpect.EOF, pexpect.TIMEOUT],
            timeout=10,
        )
        if idx == 0:
            child.sendline(password)
            # After sending password, wait for either EOF (success) or second prompt (wrong pw)
            idx2 = child.expect(
                [r"[Ss]orry, try again", pexpect.EOF, pexpect.TIMEOUT],
                timeout=10,
            )
            if idx2 == 0:
                sudo_cache.SudoCache.clear()
                raise RuntimeError(
                    "Wrong sudo password. Password cache has been cleared. "
                    "Send /sudopass <new-password> with the correct password."
                )
            elif idx2 == 2:
                raise RuntimeError("Sudo command timed out waiting for output.")
        elif idx == 1:
            sudo_cache.SudoCache.clear()
            raise RuntimeError(
                "Wrong sudo password. Password cache has been cleared. "
                "Send /sudopass <new-password> with the correct password."
            )
        # idx == 2 means EOF -- command completed without asking for password (NOPASSWD)
        # idx == 3 means TIMEOUT -- something unexpected happened

        child.wait()
        output = (child.before or "").strip()

        if child.exitstatus and child.exitstatus != 0:
            output = f"Exit code: {child.exitstatus}\n\n{output}"

        if not output:
            output = "(no output)"

        for chunk in formatter.split_messages(output):
            await update.message.reply_text(formatter.wrap_code(chunk))

    except pexpect.ExceptionPexpect as exc:
        logger.error("pexpect error: %s", exc)
        await update.message.reply_text(f"Sudo command failed: {exc}")
    except Exception as exc:
        logger.exception("Unexpected sudo error")
        await update.message.reply_text(f"Sudo command failed: {exc}")


async def cmd_term(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Open a program in a new terminal: /term <program>."""
    cmd = " ".join(context.args) if context.args else ""
    if not cmd:
        await update.message.reply_text("Usage: /term <program>")
        return

    terminals = [
        ("kitty", lambda c: ["kitty", "--", "bash", "-c", c]),
        ("alacritty", lambda c: ["alacritty", "-e", "bash", "-c", c]),
        ("gnome-terminal", lambda c: ["gnome-terminal", "--", "bash", "-c", c]),
        ("xterm", lambda c: ["xterm", "-e", "bash", "-c", c]),
    ]

    terminal_cmd = None
    for binary, builder in terminals:
        rc, _, _ = await run_shell(["which", binary])
        if rc == 0:
            terminal_cmd = builder(cmd)
            break

    if terminal_cmd is None:
        await update.message.reply_text(
            "No supported terminal emulator found. Looking for: kitty, alacritty, gnome-terminal, xterm."
        )
        return

    try:
        await run_shell(terminal_cmd, env=config.x11_env())
        await update.message.reply_text(f"Opened in terminal: {cmd}")
    except Exception as exc:
        logger.exception("Terminal launch failed")
        await update.message.reply_text(f"Failed to open terminal: {exc}")


async def cmd_hotkey(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Simulate hotkeys via xdotool: /hotkey <keys>.

    Format: ctrl+shift+super+e
    """
    keys = " ".join(context.args) if context.args else ""
    if not keys:
        await update.message.reply_text(
            "Usage: /hotkey <keys> (e.g. /hotkey ctrl+shift+t)"
        )
        return

    # Translate modifier names to xdotool-compatible key names
    xdotool_key = (
        keys.lower()
        .replace("super", "super_l")
        .replace("ctrl", "ctrl_l")
        .replace("alt", "alt_l")
        .replace("shift", "shift_l")
    )

    rc, _, stderr = await run_shell(
        ["xdotool", "key", xdotool_key], env=config.x11_env()
    )

    if rc == 0:
        await update.message.reply_text(f"Sent hotkey: {keys}")
    else:
        error = stderr.strip() or "(unknown error)"
        await update.message.reply_text(
            f"Failed to send hotkey. Is xdotool installed?\n"
            f"{error}"
        )


async def cmd_screenshot(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Take a screenshot. /screenshot — full display. /screenshot region — flameshot GUI region select."""
    import asyncio
    import tempfile

    mode = (context.args[0].lower() if context.args else "full")

    if mode == "region":
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            tmp_path = tmp.name
        try:
            env = {**os.environ, **config.x11_env()}
            proc = await asyncio.create_subprocess_exec(
                "flameshot", "gui", "--raw",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
            stdout, stderr = await proc.communicate()
            if proc.returncode != 0 or not stdout:
                msg = (stderr.decode(errors="replace").strip()
                       or "Region capture cancelled or flameshot failed.")
                await update.message.reply_text(f"Region screenshot failed: {msg}")
                return
            with open(tmp_path, "wb") as f:
                f.write(stdout)
            with open(tmp_path, "rb") as f:
                await update.message.reply_photo(f, caption="Region screenshot")
        except FileNotFoundError:
            await update.message.reply_text("flameshot not installed.")
        except Exception as exc:
            logger.exception("Region screenshot failed")
            await update.message.reply_text(f"Region screenshot failed: {exc}")
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        return

    screenshot_tools = [
        ("import", ["import", "-window", "root"]),
        ("scrot", ["scrot", "-o"]),
    ]
    tool = None
    cmd_prefix: list[str] = []

    for name, prefix_args in screenshot_tools:
        rc, _, _ = await run_shell(["which", name])
        if rc == 0:
            tool = name
            cmd_prefix = prefix_args
            break

    if tool is None:
        await update.message.reply_text(
            "Screenshot tool not found. Install imagemagick (for import) or scrot."
        )
        return

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        if tool == "import":
            rc, _, stderr = await run_shell(
                cmd_prefix + [tmp_path], env=config.x11_env()
            )
        else:
            # scrot -o <path> writes directly to the given file
            rc, _, stderr = await run_shell(
                cmd_prefix + [tmp_path], env=config.x11_env()
            )

        if rc != 0:
            await update.message.reply_text(
                f"Screenshot failed. Is DISPLAY set correctly?\n"
                f"{stderr.strip()}"
            )
            os.unlink(tmp_path)
            return

        with open(tmp_path, "rb") as f:
            await update.message.reply_photo(f, caption="Screenshot")
    except Exception as exc:
        logger.exception("Screenshot failed")
        await update.message.reply_text(f"Screenshot failed: {exc}")
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
